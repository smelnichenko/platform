#!/bin/bash
# Kafka's backup (schnappy-data's kafka-backup.yaml): its dump and restore (files/kafka-backup-dump.sh, -restore.sh)
# against a stub Kafka (kafka-backup-stub-kafka.sh: topics, partitions, offsets, groups as files) - the dump exact or
# refused, the restore a round trip or refused; the prune script the same in every chart. Run on the image the
# CronJob runs them in (apache/kafka at strimzi.kafkaVersion: Alpine, busybox's awk and iconv, bash), as its user -
# the CronJob as rendered is kafka-backup-render-test.sh's, which needs helm.
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
  if env W="$T/$w" KAFKA_BIN="$T/$w/bin" BOOTSTRAP=b:9092 OUT="$T/$w/out" RESTORING="${RESTORING:-$T/no-restore}" bash "$s" "$@" > "$T/out" 2>&1; then echo rc=0; else echo rc=$?; fi
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
# each topic's retention and its checkpoints (topics/<t>.kept): messages 6.5, 3.5 and 0.5 days old, checkpoints 6..1
# days back - the first message at or after each
NOW=$(( $(date +%s) * 1000 )); DAY=86400000
A; printf '%s\n' $((NOW - 6 * DAY - DAY / 2)) $((NOW - 3 * DAY - DAY / 2)) $((NOW - DAY / 2)) > "$T/a/k/chat.messages/$P1.times"
echo $((2 * DAY)) > "$T/a/k/user.events/retention"
r=$(run a "$DUMP"); dk=$(ls "$T/a/out" | head -1)
check "the dump records each topic's retention and, per partition, its first offset at each checkpoint (none - left out)" \
  "$r $(sed -n 's/^retention://p' "$T/a/out/$dk/topics/chat.messages.kept") $(grep -v '^[ar]' "$T/a/out/$dk/topics/chat.messages.kept" | cut -d: -f2- | sort -t: -k2,2n | tr '\n' ' ')" \
  "rc=0 604800000 $P1:6 $P1:6 $P1:6 $P1:7 $P1:7 $P1:7 "
at=$(sed -n 's/^at://p' "$T/a/out/$dk/topics/chat.messages.kept")
check "  its checkpoints: the dump's time - the retention + 1..6 days" \
  "$(grep -v '^[ar]' "$T/a/out/$dk/topics/chat.messages.kept" | cut -d: -f1 | sort -un | awk -v a="$at" -v D="$DAY" '{ printf "%d ", ($1 - a + 7 * D) / D }')" "1 2 3 4 5 6 "
check "  a topic's own retention (2 days): its checkpoint asked apart (1 day back) - one read of every topic per checkpoint, 6 + 1" \
  "$(sed -n 's/^retention://p' "$T/a/out/$dk/topics/user.events.kept") $(grep -c 'kafka-get-offsets.sh .*--exclude-internal-topics --time' "$T/a/calls")" \
  "$((2 * DAY)) 7"
check "  local.retention.ms (-2, printed first by Kafka 4) never read as the retention" "$(grep -c '^chat.messages -2$' "$T/a/out/$dk/retention.txt") $(find "$T/a/out/$dk" -maxdepth 1 -name 'at.*' | wc -l)" "0 0"
A; echo -1 > "$T/a/k/user.events/retention"; echo $((30 * DAY)) > "$T/a/k/chat.messages/retention"
r=$(run a "$DUMP"); dk=$(ls "$T/a/out" | head -1)
check "  retention -1 (for ever): its record, no checkpoint asked; 30 days: two weeks of checkpoints at most (14 reads)" \
  "$r $(sed -n 's/^retention://p' "$T/a/out/$dk/topics/user.events.kept") $(grep -c 'kafka-get-offsets.sh .*--exclude-internal-topics --time' "$T/a/calls")" \
  "rc=0 -1 14"
A; r=$(NO_RETENTION=user.events run a "$DUMP"); dk=$(ls "$T/a/out" | head -1)
check "  a topic's retention not read: refused, no DONE" "$r $(grep -c 'no retention read for: user.events' "$T/out") $([ -f "$T/a/out/$dk/DONE" ] && echo done || echo none)" "rc=1 1 none"
# the first world's dump again, alone in its out directory (two dumps in one second share a name)
A; run a "$DUMP" > /dev/null; d=$(ls "$T/a/out" | head -1)
# the restore into a fresh world with the same topics, empty: the round trip
world b; topic b chat.messages 2; topic b user.events 1
r=$(run b "$RESTORE" "$T/a/out/$d")
check "a restore: every message back, each keyed one on its partition and in its order, headers as they were" \
  "$r $(cmp -s "$T/a/k/chat.messages/$P1.log" "$T/b/k/chat.messages/$P1.log" && echo same-p0) $(cmp -s "$T/a/k/user.events/0.log" "$T/b/k/user.events/0.log" && echo same-ue) $(tail -1 "$T/out")" \
  "rc=0 same-p0 same-ue restored 4 messages from $d"
check "  the topics restored said before it (ops' BASELINE names these alone)" "$(tail -2 "$T/out" | head -1)" "topics chat.messages user.events "
world tt; topic tt chat.messages 2; topic tt user.events 1
r=$(TOPICS=chat.messages run tt "$RESTORE" "$T/a/out/$d")
check "  TOPICS named: the topics line names those alone - a BASELINE of one topic never covers another" "$r $(tail -2 "$T/out" | head -1)" "rc=0 topics chat.messages"
check "  no dump or restore call with --consumer-property, --producer-property, --property, --consumer.config or --producer.config (the old spellings: Kafka 4.3 prints the deprecations it knows on stdout)" \
  "$(cat "$T/a/calls" "$T/b/calls" | grep -c -E -- '--(consumer|producer)-property |--property |--(consumer|producer)\.config ' || true)" 0
check "  synchronous sends, none held by the producer's linger (1 s each by default); the dumped group moved to the topic's end after" \
  "$(grep -c 'kafka-console-producer.sh .*--sync --command-property linger.ms=0 ' "$T/b/calls") $(grep -c 'kafka-consumer-groups.sh .*--group user-sync --topic user.events --reset-offsets --to-latest --execute' "$T/b/calls")" \
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
check "a dump refused: a read short of its offsets' count (every line a message: none named), the consumer's stderr shown" \
  "$r $(grep -c 'messages read, its offsets say [0-9]*$' "$T/out") $(grep -c '^Processed a total of 2 messages$' "$T/out")" "rc=1 1 1"
A; r=$(START_SHIFT=1 run a "$DUMP")
check "a dump refused: retention moved a log's start past its offset after the offsets read - an error (auto.offset.reset=none), no silent jump" \
  "$r $(grep -c 'the read failed' "$T/out") $(grep -c 'OffsetOutOfRangeException' "$T/out")" "rc=1 1 1"
# Kafka 4.3's console consumer prints a deprecated option's notice on stdout, among the messages: the dump with the old
# spelling refused, the notice named (a tool's own line); a value's fragment counted but its text never logged
A; sed 's/--command-property auto\.offset\.reset=none/--consumer-property auto.offset.reset=none/' "$DUMP" > "$T/dump-deprecated.sh"
check "  (the old spelling put back into a copy of the dump: the sed matched its read's line)" \
  "$(cmp -s "$DUMP" "$T/dump-deprecated.sh" && echo 'unchanged - the dump no longer reads with --command-property auto.offset.reset=none' || echo changed)" changed
r=$(run a "$T/dump-deprecated.sh")
check "a dump refused: a tool's notice on stdout among the messages (the deprecated --consumer-property), the line named" \
  "$r $(grep -c 'messages read, its offsets say [0-9]*; not a message: line 1 ([0-9]* characters): Option --consumer-property is deprecated' "$T/out")" "rc=1 1"
A; r=$(EXTRA_LINE='private chat text' run a "$DUMP")
check "a dump refused: a line that is no message (a value split at a raw newline) - named by number and length, its text never logged" \
  "$r $(grep -c 'messages read, its offsets say [0-9]*; not a message: line 2 (17 characters)$' "$T/out") $(grep -c 'private chat text' "$T/out" || true)" "rc=1 1 0"
A; printf 'NO_HEADERS\tu9\t{"x":"a\rb"}\n' >> "$T/a/k/chat.messages/$P0.log"; r=$(run a "$DUMP")
check "a dump refused: a carriage return in a message" "$r $(grep -c 'a carriage return' "$T/out")" "rc=1 1"
A; printf 'NO_HEADERS\tu9\t{"x":"\377"}\n' >> "$T/a/k/chat.messages/$P0.log"; r=$(run a "$DUMP")
check "a dump refused: a message not valid UTF-8" "$r $(grep -c 'not valid UTF-8' "$T/out")" "rc=1 1"
A; printf 'NO_HEADERS\tonly-two-fields\n' >> "$T/a/k/chat.messages/$P0.log"; r=$(run a "$DUMP")
check "a dump refused: a line with fewer than three fields" "$r $(grep -c 'fewer than three fields' "$T/out")" "rc=1 1"
world e; r=$(run e "$DUMP")
check "a dump refused: no topic at all (a Kafka that lost its data)" "$r $(grep -c 'no topic in Kafka' "$T/out")" "rc=1 1"
A; echo 20261118T020000Z > "$T/restoring"; r=$(RESTORING="$T/restoring" run a "$DUMP")
check "a dump refused: a restore running (its ConfigMap's since) - Kafka not even listed, no DONE" \
  "$r $(grep -c 'a restore running since 20261118T020000Z' "$T/out") $(cat "$T/a/calls" 2> /dev/null | grep -c 'kafka-topics.sh' || true) $(ls "$T"/a/out/*/DONE 2> /dev/null | wc -l | tr -d ' ')" "rc=1 1 0 0"
A; echo 20261118T030000Z > /dev/null; r=$(MAKE_RESTORING="$T/restoring-late" RESTORING="$T/restoring-late" run a "$DUMP")
check "a dump refused: a restore begun while it read (the ConfigMap appearing) - no DONE" \
  "$r $(grep -c 'a restore began while dumping' "$T/out") $(ls "$T"/a/out/*/DONE 2> /dev/null | wc -l | tr -d ' ')" "rc=1 1 0"
rm -f "$T/restoring-late"
# the restore checks the dump against itself first: a partition's file cut short, a DONE disagreeing - nothing produced
A; r=$(run a "$DUMP"); d=$(ls "$T/a/out" | head -1)
mkdir -p "$T/y"; rm -rf "${T:?}/y/$d"; cp -r "$T/a/out/$d" "$T/y/"; sed -i '$d' "$T/y/$d/topics/chat.messages.$P1.messages"
world b; topic b chat.messages 2; topic b user.events 1
r=$(run b "$RESTORE" "$T/y/$d")
check "a restore refused: a partition's file short of its offsets' count - damaged, nothing produced" \
  "$r $(grep -c "chat.messages\[$P1\]: the dump holds 2 messages, its offsets say 3 - damaged" "$T/out") $(cat "$T/b/calls" 2> /dev/null | grep -c 'kafka-console-producer' || true)" "rc=1 1 0"
rm -rf "${T:?}/y/$d"; cp -r "$T/a/out/$d" "$T/y/"; sed -i 's/ 4 messages$/ 5 messages/' "$T/y/$d/DONE"
world b; topic b chat.messages 2; topic b user.events 1
r=$(run b "$RESTORE" "$T/y/$d")
check "a restore refused: DONE counting other than the files hold" "$r $(grep -c 'its DONE says 5 - damaged' "$T/out")" "rc=1 1"
# the guard before the upload (files/kafka-backup-guard.sh) against a stub rclone over a store of directories
mkdir -p "$T/rbin"
cat > "$T/rbin/rclone" << 'STUB'
#!/bin/sh
p() { echo "$T/store/${1#store:}"; }
# FAIL_LSF: every listing fails; FAIL_ON "<call> <path>" one read alone (lsf-dirs, lsf-files, cat, copy)
last=$(eval echo "\${$#}")
case "$1 $*" in lsf*--dirs-only*) key="lsf-dirs $last" ;; lsf*) key="lsf-files $last" ;; *) key="$1 $2" ;; esac
[ "${FAIL_ON:-}" != "$key" ] || { echo "stub: $key failed" >&2; exit 1; }
case "$1" in
  lsf)
    [ -z "${FAIL_LSF:-}" ] || { echo "stub: listing failed" >&2; exit 1; }
    d=$(p "$last"); [ -d "$d" ] || exit 0
    case "$*" in
      *--dirs-only*) for e in "$d"/*/; do [ -d "$e" ] && basename "$e" | sed 's#$#/#'; done ;;
      *--files-only*) for e in "$d"/*; do [ -f "$e" ] && basename "$e"; done ;;
    esac ;;
  cat) cat "$(p "$2")" ;;
  copy) src=$(p "$2"); dst=$3; [ -d "$src" ] || { echo "stub: no $2" >&2; exit 3; }
    [ -z "${FAIL_COPY:-}" ] || { echo "stub: copy failed" >&2; exit 1; }
    echo "copy $*" >> "$T/rclone-calls"
    # the --include patterns as rclone reads them (none: every file); a pattern's * never crosses a /
    shift 3; inc=""; while [ $# -gt 0 ]; do [ "$1" != --include ] || { inc="$inc $2"; shift; }; shift; done
    (cd "$src" && find . -type f | sed 's#^\./##') | while read -r f; do
      ok=""; [ -n "$inc" ] || ok=1
      set -f; for g in $inc; do case "$f" in */*) [ "${g#*/}" != "$g" ] || continue ;; esac; case "$f" in $g) ok=1 ;; esac; done; set +f
      [ -z "$ok" ] || { mkdir -p "$dst/$(dirname "$f")"; cp "$src/$f" "$dst/$f"; }
    done ;;
  *) echo "stub: unexpected $*" >&2; exit 2 ;;
esac
exit 0
STUB
chmod +x "$T/rbin/rclone"
GUARD=helm/schnappy-data/files/kafka-backup-guard.sh
guard() { if T="$T" PATH="$T/rbin:$PATH" STORE=store:b FAIL_LSF=${FAIL_LSF:-} FAIL_ON=${FAIL_ON:-} sh "$GUARD" "$1" > "$T/out" 2>&1; then echo rc=0; else echo rc=$?; fi; }
store() { rm -rf "${T:?}/store"; mkdir -p "$T/store/b"; }
put() {  # put <dump dir> <name>: the dump in the store under that name, complete
  cp -r "$1" "$T/store/b/$2"
}
A; run a "$DUMP" > /dev/null; d=$(ls "$T/a/out" | head -1); new="$T/a/out/$d"
store
check "the guard, no dump in the store yet: nothing to compare, passed" "$(guard "$new") $(grep -c 'no complete dump before this one' "$T/out")" "rc=0 1"
put "$new" 20261101T023000Z
check "  the newest complete dump the same: passed, each topic judged against it" \
  "$(guard "$new") $(grep -c 'chat.messages@20261101T023000Z user.events@20261101T023000Z' "$T/out")" "rc=0 1"
mkdir -p "$T/store/b/20261102T023000Z"
check "  a newer incomplete one passed over, the complete one compared" "$(guard "$new") $(grep -c '@20261101T023000Z' "$T/out")" "rc=0 1"
store; put "$new" 20261101T023000Z; put "$new" 29991231T000000Z; sed -i 's/TopicId: x/TopicId: later/' "$T/store/b/29991231T000000Z/topics-describe.txt"
check "  a dump begun after this one (made by hand beside the night's) never its reference" "$(guard "$new") $(grep -c '@20261101T023000Z' "$T/out")" "rc=0 1"
store; put "$new" 20261101T023000Z; echo "gone.topic" >> "$T/store/b/20261101T023000Z/topics.txt"; echo "gone.topic:0:9" > "$T/store/b/20261101T023000Z/topics/gone.topic.latest"
printf 'Topic: gone.topic\tTopicId: g\tPartitionCount: 1\n' >> "$T/store/b/20261101T023000Z/topics-describe.txt"
check "  a topic the store's dump held gone: refused" "$(guard "$new") $(grep -c 'gone.topic gone (since 20261101T023000Z) - not uploaded' "$T/out")" "rc=1 1"
store; put "$new" 20261101T023000Z; sed -i 's/TopicId: x/TopicId: old/' "$T/store/b/20261101T023000Z/topics-describe.txt"
check "  a topic made again (its TopicId changed): refused" "$(guard "$new") $(grep -c 'made again (TopicId old -> x' "$T/out")" "rc=1 1"
store; put "$new" 20261101T023000Z; sed -i "s/^chat.messages:$P1:\([0-9]*\)/chat.messages:$P1:99/" "$T/store/b/20261101T023000Z/topics/chat.messages.latest"
check "  a partition's latest offset back: refused, named" "$(guard "$new") $(grep -c "chat.messages\[$P1\] at 8, was 99" "$T/out")" "rc=1 1"
printf '20261105T000000Z\nwhy a restore\nall\n' > "$T/store/b/BASELINE"
check "  the same, the BASELINE (all) newer than every dump: nothing to compare, passed" "$(guard "$new") $(grep -c 'nothing to compare' "$T/out")" "rc=0 1"
printf '20261105T000000Z\n' > "$T/store/b/BASELINE"
check "  a BASELINE of a timestamp alone covers all" "$(guard "$new")" "rc=0"
printf '20261105T000000Z\nwhy a restore of user.events\ntopic user.events\n' > "$T/store/b/BASELINE"
check "  a BASELINE covering another topic (user.events restored): chat.messages still judged - refused" \
  "$(guard "$new") $(grep -c "chat.messages\[$P1\] at 8, was 99" "$T/out")" "rc=1 1"
printf '20261105T000000Z\nwhy a restore of chat.messages\ntopic chat.messages\n' > "$T/store/b/BASELINE"
check "  covering the topic itself: not judged against the dump before it; the others still are - passed" \
  "$(guard "$new") $(grep -c 'user.events@20261101T023000Z' "$T/out") $(grep -c 'chat.messages@' "$T/out")" "rc=0 1 0"
put "$new" 20261106T023000Z
check "  a dump since that BASELINE: the covered topic judged against it" "$(guard "$new") $(grep -c 'chat.messages@20261106T023000Z' "$T/out")" "rc=0 1"
echo nonsense > "$T/store/b/BASELINE"
check "  a BASELINE without a timestamp: refused" "$(guard "$new")" "rc=1"
store; put "$new" 20261101T023000Z; sed -i 's/TopicId: x//' "$T/store/b/20261101T023000Z/topics-describe.txt"
check "  a TopicId not read (the describe format changed): refused, never passed" "$(guard "$new") $(grep -c 'no TopicId for' "$T/out")" "rc=1 1"
store; put "$new" 20261101T023000Z
check "  the store's listing failing: refused, never 'nothing to compare'" "$(FAIL_LSF=1 guard "$new") $(grep -c 'listing store:b failed' "$T/out")" "rc=1 1"
# the retention check: the reference's record (topics/<t>.kept) against the new dump's earliest offsets
kept_ref() {  # kept_ref <at> <retention> [<time>:<p>:<offset> ...]: chat.messages' record in the store's reference
  local k="$T/store/b/20261101T023000Z/topics/chat.messages.kept" a=$1 r=$2; shift 2
  { echo "at:$a"; echo "retention:$r"; for x in "$@"; do echo "$x"; done; } > "$k"
}
A; printf '%s\n' $((NOW - 3 * DAY)) $((NOW - 2 * DAY)) $((NOW - DAY)) > "$T/a/k/chat.messages/$P1.times"
run a "$DUMP" > /dev/null; d=$(ls "$T/a/out" | head -1); new="$T/a/out/$d"
at=$(sed -n 's/^at://p' "$new/topics/chat.messages.kept"); R=$((7 * DAY))
early() { sed -i "s/^chat.messages:$P1:.*/chat.messages:$P1:$1/" "$new/topics/chat.messages.earliest"; }
store; put "$new" 20261101T023000Z; ra=$((at - DAY))
kept_ref "$ra" "$R" "$((ra - R + DAY)):$P1:5" "$((ra - R + 2 * DAY)):$P1:6" "$((ra - R + 3 * DAY)):$P1:7"
early 6
check "the guard's retention check: the earliest offset at the bound (the first checkpoint not older than now - its retention) - passed" \
  "$(guard "$new") $(grep -c 'retention not judged' "$T/out")" "rc=0 0"
early 7
check "  past it (messages its retention keeps gone - TopicId and latest offsets as they were): refused, named" \
  "$(guard "$new") $(grep -c "chat.messages\[$P1\] begins at 7, 20261101T023000Z's retention keeps it from 6" "$T/out")" "rc=1 1"
kept_ref "$ra" "$R"
early 8
check "  no checkpoint holding the partition (no message that young): bounded by its latest - 8 passes, 9 refused" \
  "$(guard "$new") $(early 9; guard "$new")" "rc=0 rc=1"
kept_ref "$((at - R))" "$R" "$((at - 2 * R + DAY)):$P1:5"
check "  a reference older than its retention lets judge: said, not judged" \
  "$(guard "$new") $(grep -c 'retention not judged for chat.messages (older than its retention lets judge)' "$T/out")" "rc=0 1"
rm "$T/store/b/20261101T023000Z/topics/chat.messages.kept"
check "  a reference with no record (a dump before the check): said, not judged" \
  "$(guard "$new") $(grep -c 'retention not judged for chat.messages (no retention record)' "$T/out")" "rc=0 1"
kept_ref "$ra" -1
early 6
check "  retention -1 (kept for ever): the earliest past the reference's (5): refused" \
  "$(guard "$new") $(grep -c "begins at 6, 20261101T023000Z's retention keeps it from 5" "$T/out")" "rc=1 1"
kept_ref "$((at - 2 * DAY))" "$((2 * DAY))" "$((at - 3 * DAY)):$P1:7"
check "  the reference's retention, not today's: 2 days then, the reference 2 days old - older than it lets judge (7 days would)" \
  "$(guard "$new") $(grep -c 'older than its retention lets judge' "$T/out")" "rc=0 1"
# covered by a BASELINE, its reference made since it: judged - its retention too
kept_ref "$ra" "$R" "$((ra - R + DAY)):$P1:5" "$((ra - R + 2 * DAY)):$P1:6"; early 7
printf '20261031T000000Z\nwhy a restore\ntopic chat.messages\n' > "$T/store/b/BASELINE"
check "  covered by a BASELINE older than the reference: judged, its retention too - refused" \
  "$(guard "$new") $(grep -c "chat.messages\[$P1\] begins at 7" "$T/out")" "rc=1 1"
rm "$T/store/b/BASELINE"; early 5
# one store read failing alone: refused, never "nothing to compare" or a reference passed over
printf '20261031T000000Z\nall\n' > "$T/store/b/BASELINE"
check "a store read failing alone - the BASELINE's: refused" "$(FAIL_ON='cat store:b/BASELINE' guard "$new") $(grep -c 'reading store:b/BASELINE failed' "$T/out")" "rc=1 1"
rm "$T/store/b/BASELINE"
check "  the store's dumps listed: refused (never 'no complete dump before this one')" "$(FAIL_ON='lsf-dirs store:b/' guard "$new") $(grep -c 'no complete dump before' "$T/out")" "rc=1 0"
check "  the reference's files listed: refused (never passed over for an older one)" \
  "$(FAIL_ON='lsf-files store:b/20261101T023000Z/' guard "$new") $(grep -c 'listing store:b/20261101T023000Z failed' "$T/out")" "rc=1 1"
# a partition gone; a TopicId the new dump's description lacks; the reference's offsets missing
store; put "$new" 20261101T023000Z; mkdir -p "$T/n2"; cp -r "$new" "$T/n2/"; n2="$T/n2/$(basename "$new")"
sed -i "/^chat.messages:$P1:/d" "$n2/topics/chat.messages.latest"
check "a partition the reference held gone from the new dump: refused, named" "$(guard "$n2") $(grep -c "chat.messages\[$P1\] gone" "$T/out")" "rc=1 1"
rm -rf "$T/n2"; mkdir -p "$T/n2"; cp -r "$new" "$T/n2/"; sed -i 's/TopicId: x//' "$n2/topics-describe.txt"
check "  the new dump's TopicId not read: refused" "$(guard "$n2") $(grep -c 'no TopicId for' "$T/out")" "rc=1 1"
rm -rf "$T/n2"; rm "$T/store/b/20261101T023000Z/topics/user.events.earliest"
check "  the reference's offsets for a topic missing: refused, the retire task named" "$(guard "$new") $(grep -c 'holds no offsets for user.events' "$T/out")" "rc=1 1"
# a BASELINE covers whole names: user.events.dlt covered never excuses user.events (a name inside another)
store; put "$new" 20261101T023000Z; sed -i 's/TopicId: x/TopicId: old/' "$T/store/b/20261101T023000Z/topics-describe.txt"
printf '20261105T000000Z\nwhy x\ntopic user.events.dlt\ntopic chat.messages\n' > "$T/store/b/BASELINE"
check "  a BASELINE of user.events.dlt: user.events still judged (whole names) - refused, chat.messages excused" \
  "$(guard "$new") $(grep -c 'user.events made again' "$T/out") $(grep -c 'chat.messages made again' "$T/out")" "rc=1 1 0"
# a damaged reference: what a BASELINE excused is never read; else refused, the way out named
store; put "$new" 20261101T023000Z; rm "$T/store/b/20261101T023000Z/topics.txt"; printf '20261105T000000Z\nwhy x\nall\n' > "$T/store/b/BASELINE"
: > "$T/rclone-calls"
check "a damaged reference (no topics.txt) a BASELINE of all covers, it older: passed, never read" \
  "$(guard "$new") $(grep -c 'nothing to compare' "$T/out") $(grep -c '^copy' "$T/rclone-calls")" "rc=0 1 0"
rm "$T/store/b/BASELINE"
check "  no BASELINE: refused, ops' retire task named" "$(guard "$new") $(grep -c 'holds no topics.txt: not uploaded (a damaged dump: ops. task deploy:kafka-backup-retire)' "$T/out")" "rc=1 1"
store; put "$new" 20261101T023000Z
check "  its read failing: refused" "$(FAIL_COPY=1 guard "$new") $(grep -c "reading 20261101T023000Z's offsets failed" "$T/out")" "rc=1 1"
[ "$fails" -eq 0 ] && echo "kafka backup test: OK" || { echo "kafka backup test: $fails FAILED"; exit 1; }
