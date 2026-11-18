#!/bin/bash
# Kafka's backup (schnappy-data's kafka-backup.yaml): its dump and restore (files/kafka-backup-dump.sh, -restore.sh)
# against a stub Kafka (kafka-backup-stub-kafka.sh: topics, partitions, offsets, groups as files) - the dump exact or
# refused, the restore a round trip or refused; its CronJob as rendered; the prune script the same in every chart.
set -eu
fails=0
check() { if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1: got '$2', want '$3'"; fails=$((fails + 1)); fi; }
check "the prune script: schnappy-data's copy the same as schnappy-observability's" \
  "$(cmp -s helm/schnappy-data/files/backup-prune.sh helm/schnappy-observability/files/backup-prune.sh && echo same || echo differ)" same
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
DUMP=helm/schnappy-data/files/kafka-backup-dump.sh
RESTORE=helm/schnappy-data/files/kafka-backup-restore.sh
TAB=$(printf '\t'); RS=$(printf '\036')
world() {  # world <name>: a fresh stub Kafka
  rm -rf "${T:?}/$1"; mkdir -p "$T/$1"; sh .woodpecker/kafka-backup-stub-kafka.sh "$T/$1"
}
topic() {  # topic <world> <name> <partitions> [<p>:<line> ...]
  local w=$1 t=$2 n=$3; shift 3; mkdir -p "$T/$w/k/$t"; echo "$n" > "$T/$w/k/$t/parts"
  for x in "$@"; do printf '%s\n' "${x#*:}" >> "$T/$w/k/$t/${x%%:*}.log"; done
}
run() {  # run <world> <script> [args]: its rc (its output in $T/out)
  local w=$1 s=$2; shift 2
  if env W="$T/$w" KAFKA_BIN="$T/$w/bin" BOOTSTRAP=b:9092 OUT="$T/$w/out" bash "$s" "$@" > "$T/out" 2>&1; then echo rc=0; else echo rc=$?; fi
}
# a world as production's: keyed messages with headers (a JSON type header with commas and colons), header-less ones, a
# null key; an empty partition; a log start past 0 (retention); a group
# u1's partition as the producer's hash puts it (the stub's: cksum of the key, modulo the partitions)
P1=$(( $(printf u1 | cksum | cut -d' ' -f1) % 2 )); P0=$((1 - P1))
A() {
  world a
  topic a chat.messages 2 "$P1:__TypeId__:x.Y${RS}spring_json_header_types:{\"a\":\"b\",\"c\":\"d\"}${TAB}u1${TAB}{\"t\":\"one, two: three\"}" \
    "$P1:NO_HEADERS${TAB}u1${TAB}{\"n\":2}" "$P1:h:v${TAB}u1${TAB}{\"n\":3}"
  echo 5 > "$T/a/k/chat.messages/$P1.start"
  topic a user.events 1 "0:NO_HEADERS${TAB}__NULL__${TAB}{\"e\":1}"
  echo "user-sync user.events 0 1" > "$T/a/k/groups"
}
A; r=$(run a "$DUMP"); d=$(ls "$T/a/out" 2> /dev/null | head -1)
check "a dump: each partition from its earliest offset (5) for its count, the empty one skipped, DONE with the totals" \
  "$r $(grep -c "kafka-console-consumer.sh .*--partition $P1 --offset 5 --max-messages 3 .*--command-property auto.offset.reset=none" "$T/a/calls") $(grep -c "kafka-console-consumer.sh .*--topic chat.messages --partition $P0 " "$T/a/calls" || true) $(cut -d' ' -f2- "$T/a/out/$d/DONE")" \
  "rc=0 1 0 2 topics 4 messages"
# the restore into a fresh world with the same topics, empty: the round trip
world b; topic b chat.messages 2; topic b user.events 1
r=$(run b "$RESTORE" "$T/a/out/$d")
check "a restore: every message back, each keyed one on its partition and in its order, headers as they were" \
  "$r $(cmp -s "$T/a/k/chat.messages/$P1.log" "$T/b/k/chat.messages/$P1.log" && echo same-p0) $(cmp -s "$T/a/k/user.events/0.log" "$T/b/k/user.events/0.log" && echo same-ue) $(tail -1 "$T/out")" \
  "rc=0 same-p0 same-ue restored 4 messages from $d"
check "  no Kafka tool called with a deprecated option (Kafka 4.3 prints their notices on stdout), dump or restore" \
  "$(cat "$T/a/calls" "$T/b/calls" | grep -c -E -- '--(consumer|producer)-property |--property ' || true)" 0
check "  synchronous sends; the dumped group moved to the topic's end after" \
  "$(grep -c 'kafka-console-producer.sh .*--sync' "$T/b/calls") $(grep -c 'kafka-consumer-groups.sh .*--group user-sync --topic user.events --reset-offsets --to-latest --execute' "$T/b/calls")" \
  "4 1"
r=$(run b "$RESTORE" "$T/a/out/$d")
check "  run again: each topic holding the dump's messages already - skipped, nothing produced twice" \
  "$r $(grep -c 'holds the dump.s .* messages already - skipped' "$T/out") $(wc -l < "$T/b/k/chat.messages/$P1.log" | tr -d ' ')" "rc=0 2 3"
# the restore's refusals - nothing produced
world c; topic c chat.messages 2
r=$(run c "$RESTORE" "$T/a/out/$d")
check "refused: a topic of the dump missing (user.events)" "$r $(grep -c 'user.events: no such topic' "$T/out") $(ls "$T/c/k/chat.messages" | grep -c log || true)" "rc=1 1 0"
world c; topic c chat.messages 3; topic c user.events 1
r=$(run c "$RESTORE" "$T/a/out/$d")
check "refused: a topic with other partitions than the dump's" "$r $(grep -c 'chat.messages: 3 partitions, the dump.s 2' "$T/out")" "rc=1 1"
world c; topic c chat.messages 2 "1:NO_HEADERS${TAB}z${TAB}{}"; topic c user.events 1
r=$(run c "$RESTORE" "$T/a/out/$d")
check "refused: a topic in use (holding other messages)" "$r $(grep -c 'chat.messages: holds 1 messages' "$T/out")" "rc=1 1"
world c; topic c chat.messages 2; topic c user.events 1; echo "user-sync user.events 0 1" > "$T/c/k/groups"; echo 1 > "$T/c/k/members/user-sync"
r=$(run c "$RESTORE" "$T/a/out/$d")
check "refused: a consumer group live on a restored topic" "$r $(grep -c 'live on the topics: user-sync' "$T/out") $(ls "$T/c/k/chat.messages" | grep -c log || true)" "rc=1 1 0"
world c; topic c chat.messages 2; topic c user.events 1
r=$(TOPICS=chat.mesages run c "$RESTORE" "$T/a/out/$d")
check "refused: a topic named (TOPICS) not in the dump" "$r $(grep -c 'chat.mesages: not in the dump' "$T/out")" "rc=1 1"
r=$(LOSE=1 run c "$RESTORE" "$T/a/out/$d")
check "refused: a message unacknowledged (the topic's end short of the dump's count)" "$r $(grep -c 'its end offsets grew by' "$T/out")" "rc=1 1"
world c; topic c chat.messages 2; topic c user.events 1
mkdir -p "$T/x"; cp -r "$T/a/out/$d" "$T/x/"; printf 'NO_HEADERS\tk\t{}\n' > "$T/x/$d/topics/chat.messages.DLT.0.messages"
r=$(TOPICS=chat.messages run c "$RESTORE" "$T/x/$d")
check "  a child topic's file (chat.messages.DLT) never produced into its parent" "$r $(cat "$T/c/k/chat.messages"/*.log | wc -l | tr -d ' ')" "rc=0 3"
rm "$T/a/out/$d/DONE"; r=$(run b "$RESTORE" "$T/a/out/$d")
check "refused: a dump without DONE (incomplete)" "$r $(grep -c 'no DONE' "$T/out")" "rc=1 1"
# the dump's refusals - no DONE
A; r=$(DROP_PART=chat.messages:$P0 run a "$DUMP"); d=$(ls "$T/a/out" | head -1)
check "a dump refused: a partition missing from the offsets read (no leader)" \
  "$r $(grep -c 'chat.messages: the earliest offsets name partitions' "$T/out") $(test -f "$T/a/out/$d/DONE" && echo done || echo no-done)" "rc=1 1 no-done"
A; r=$(SHORT=1 run a "$DUMP")
check "a dump refused: a read short of its offsets' count (every line a message: none named)" "$r $(grep -c 'messages read, its offsets say [0-9]*$' "$T/out")" "rc=1 1"
A; r=$(START_SHIFT=1 run a "$DUMP")
check "a dump refused: retention moved a log's start past its offset after the offsets read - an error (auto.offset.reset=none), no silent jump" \
  "$r $(grep -c 'the read failed' "$T/out") $(grep -c 'OffsetOutOfRangeException' "$T/out")" "rc=1 1 1"
# Kafka 4.3's console consumer prints a deprecated option's notice on stdout, among the messages (copy run 6, 2026-11-18:
# the dump refused "1001 messages read, its offsets say 1000"): the dump as it was refused, the line named
A; sed 's/--command-property auto\.offset\.reset=none/--consumer-property auto.offset.reset=none/' "$DUMP" > "$T/dump-deprecated.sh"
check "  (the old spelling put back into a copy of the dump: the sed matched its read's line)" \
  "$(cmp -s "$DUMP" "$T/dump-deprecated.sh" && echo 'unchanged - the dump no longer reads with --command-property auto.offset.reset=none' || echo changed)" changed
r=$(run a "$T/dump-deprecated.sh")
check "a dump refused: a tool's notice on stdout among the messages (the deprecated --consumer-property), the line named" \
  "$r $(grep -c 'messages read, its offsets say [0-9]*; not a message: Option --consumer-property is deprecated' "$T/out")" "rc=1 1"
A; printf 'NO_HEADERS\tu9\t{"x":"a\rb"}\n' >> "$T/a/k/chat.messages/$P0.log"; r=$(run a "$DUMP")
check "a dump refused: a carriage return in a message" "$r $(grep -c 'a carriage return' "$T/out")" "rc=1 1"
A; printf 'NO_HEADERS\tu9\t{"x":"\377"}\n' >> "$T/a/k/chat.messages/$P0.log"; r=$(run a "$DUMP")
check "a dump refused: a message not valid UTF-8" "$r $(grep -c 'not valid UTF-8' "$T/out")" "rc=1 1"
A; printf 'NO_HEADERS\tonly-two-fields\n' >> "$T/a/k/chat.messages/$P0.log"; r=$(run a "$DUMP")
check "a dump refused: a line with fewer than three fields" "$r $(grep -c 'fewer than three fields' "$T/out")" "rc=1 1"
world e; r=$(run e "$DUMP")
check "a dump refused: no topic at all (a Kafka that lost its data)" "$r $(grep -c 'no topic in Kafka' "$T/out")" "rc=1 1"
# the CronJob as rendered
kb() { helm template t helm/schnappy-data/ --namespace schnappy-production --set postgres.password=test --set strimzi.enabled=true \
  --set strimzi.backup.enabled=true --set vault.secretsEnabled=true --set alerts.enabled=true "$@" 2>&1 || true; }
out=$(kb --set strimzi.backup.endpoint=http://192.168.11.5:9000 --set 'strimzi.backup.storeIps={192.168.11.4,192.168.11.5,192.168.11.6}' \
  --set strimzi.kafkaVersion=4.3.1)
cj() { printf '%s\n' "$out" | awk '/^kind: CronJob/ { c = 1 } /^---/ { c = 0 } c'; }
check "the CronJob: the dump in apache/kafka at the cluster's version, one try a night" \
  "$(cj | grep -c 'image: apache/kafka:4.3.1$') $(cj | awk '/backoffLimit:/ { print $2; exit }')" "1 0"
check "  in the mesh with a native sidecar (Kafka's 9092 is STRICT mTLS; the proxy up before the dump's init container), the store past it" \
  "$(cj | grep -c 'sidecar.istio.io/nativeSidecar: "true"') $(cj | grep -c 'sidecar.istio.io/inject: "false"') $(cj | grep -c 'excludeOutboundIPRanges: 192.168.11.4/32,192.168.11.5/32,192.168.11.6/32$')" \
  "1 0 1"
cp_line=$(cj | grep -n 'rclone copy "/dump/$d" "$STORE/$d" --exclude DONE' | cut -d: -f1)
done_line=$(cj | grep -n 'rclone copyto "/dump/$d/DONE"' | cut -d: -f1)
check "  its own ServiceAccount (its mesh identity, for an allow-list on Kafka), no token mounted" \
  "$(printf '%s\n' "$out" | awk '/^kind: ServiceAccount/ { s = 1 } /^---/ { s = 0 } s && /^  name: .*-kafka-backup$/ { n++ } END { print n + 0 }') $(cj | grep -c 'serviceAccountName: .*-kafka-backup$') $(cj | grep -c 'automountServiceAccountToken: false')" \
  "1 1 1"
check "  the upload: the dump without DONE first, DONE after it; the prune for the dumps' layout (root, DONE)" \
  "$([ -n "$cp_line" ] && [ -n "$done_line" ] && [ "$cp_line" -lt "$done_line" ] && echo ordered || echo not-ordered) $(cj | grep -E '\{ name: (PREFIX|MARKER), value:' | tr -d ' ' | tr '\n' ';')" \
  'ordered -{name:PREFIX,value:""};-{name:MARKER,value:DONE};'
check "  the store's keys its own ExternalSecret's (Vault's backup-store), never the CNPG backup Secret" \
  "$(printf '%s\n' "$out" | awk '/^kind: ExternalSecret/ { e = 1 } /^---/ { e = 0 } e && /^  name: .*-kafka-backup-store$/ { n++ } END { print n + 0 }') $(cj | grep -A1 'secretKeyRef' | grep -c 'name: .*-kafka-backup-store')" \
  "1 2"
check "  its pods' egress to the store's three addresses on 9000; KafkaBackupsUnwatched with it" \
  "$(printf '%s\n' "$out" | awk '/^---/ { n = 0 } /^kind: NetworkPolicy/ { k = 1 } /^kind: / && !/NetworkPolicy/ { k = 0 } k && /^  name: .*-kafka-backup$/ { n = 1 } n && /cidr: 192.168.11.[456]\/32/ { c++ } n && /port: 9000/ { p++ } END { print c + 0, p + 0 }') $(printf '%s\n' "$out" | grep -c 'alert: KafkaBackupsUnwatched')" \
  "3 1 1"
check "refused: no endpoint form, no store addresses, no Vault, keep under 2" \
  "$(kb --set strimzi.backup.endpoint=x --set 'strimzi.backup.storeIps={1.2.3.4}' | grep -c 'execution error.*backup.endpoint') $(kb --set strimzi.backup.endpoint=http://s:9000 | grep -c 'execution error.*storeIps') $(kb --set strimzi.backup.endpoint=http://s:9000 --set 'strimzi.backup.storeIps={1.2.3.4}' --set vault.secretsEnabled=false | grep -c 'execution error.*vault') $(kb --set strimzi.backup.endpoint=http://s:9000 --set 'strimzi.backup.storeIps={1.2.3.4}' --set strimzi.backup.keep=1 | grep -c 'execution error.*keep')" \
  "1 1 1 1"
check "off by default: no Kafka backup at all" \
  "$(helm template t helm/schnappy-data/ --set postgres.password=test --set strimzi.enabled=true | grep -c 'kafka-backup')" 0
[ "$fails" -eq 0 ] && echo "kafka backup test: OK" || { echo "kafka backup test: $fails FAILED"; exit 1; }
