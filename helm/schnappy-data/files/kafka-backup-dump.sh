#!/bin/bash
# Kafka's topics dumped under $OUT/<UTC timestamp>/ (an emptyDir the upload then ships to the Pi store): the topics'
# descriptions, the consumer groups' committed offsets, and every message each partition holds - read from its earliest
# offset, exactly as many as its offsets say (latest - earliest, fixed before the read: a message written meanwhile is
# the next night's), each line its headers, key and value (tab-separated; headers apart by 0x1e - Spring's JSON type
# header holds commas; a header's key and value by the formatter's fixed ':', the producer splitting at the first one - no
# header key holds one; NO_HEADERS for none). DONE written last. Refused, no DONE (a dump that would not restore as it was
# is no dump):
#   - a restore running (RESTORING, the restoring ConfigMap's key the CronJob mounts optionally: ops'
#     tasks/kafka-restore.yml makes it for the restore's span) - at the start, and again before DONE (once kubelet has
#     refreshed the volume; the restore itself refuses to start while a dump runs) - a dump of a Kafka half restored is
#     no dump of it
#   - no topic at all (a Kafka that lost its data would otherwise prune every good dump away within a week)
#   - a partition missing from the offsets read (every partition 0..PartitionCount-1, from the topic's description)
#   - a read not of its offsets' count (one message per line: a value holding a newline breaks it; a tool's notice on
#     stdout adds a line - Kafka 4.3's console consumer prints one there for a deprecated option)
#   - a carriage return, a line not valid UTF-8, or one with fewer than three fields (the producer's line reader would
#     split, mangle or misparse it)
#   - a topic whose retention is not read (the guard judges the next dumps by it)
# The read never jumps: auto.offset.reset=none - retention moving the log start past the first offset is an error, not
# a silent reset to the log's end. Given as --command-property (Kafka 4.3: --consumer-property is deprecated, and its
# notice goes to stdout - among the messages).
# Each topic's retention in force (its own or the broker's: kafka-configs --all says the value that holds) goes in
# topics/<topic>.kept with, per partition, its first offset at or after each checkpoint - the dump's time - retention + k
# days (k = 1 .. its days - 1, two weeks at most): the next dumps' guard (kafka-backup-guard.sh) judges by them whether
# Kafka still holds what this retention keeps - a retention cut short, records deleted, a clock stepped forward lose
# messages while the TopicId and the latest offsets stay. One read of every topic per checkpoint.
set -euo pipefail
K=${KAFKA_BIN:-/opt/kafka/bin}
BS=${BOOTSTRAP:?}
ts=$(date -u +%Y%m%dT%H%M%SZ)
out=${OUT:?}/$ts
mkdir -p "$out/topics"
fail() { echo "$*"; exit 1; }
RESTORING=${RESTORING:-/restoring/since}
[ ! -e "$RESTORING" ] || fail "a restore running since $(cat "$RESTORING") - no dump of a Kafka half restored"
"$K/kafka-topics.sh" --bootstrap-server "$BS" --list --exclude-internal | sort > "$out/topics.txt"
[ -s "$out/topics.txt" ] || fail "no topic in Kafka - nothing dumped (a dump of nothing would prune the good ones away)"
"$K/kafka-topics.sh" --bootstrap-server "$BS" --describe --exclude-internal > "$out/topics-describe.txt"
"$K/kafka-consumer-groups.sh" --bootstrap-server "$BS" --describe --all-groups --offsets > "$out/groups.txt" 2>&1 \
  || { cat "$out/groups.txt"; fail "the consumer groups' offsets not read"; }
"$K/kafka-configs.sh" --bootstrap-server "$BS" --describe --entity-type topics --all > "$out/topics-configs.txt" 2>&1 \
  || { cat "$out/topics-configs.txt"; fail "the topics' configs not read"; }
now=$(( $(date +%s) * 1000 ))
day=86400000
# "<topic> <retention.ms>" for each topic dumped; -1: kept for ever (its earliest offset never moves - no checkpoint)
awk 'NR == FNR { want[$1] = 1; next }
     /^All configs for topic [^ ]+ are:$/ { t = $5 }
     /^  retention\.ms=-?[0-9]+ / && (t in want) { split($1, a, "="); print t, a[2]; t = "" }' \
  "$out/topics.txt" "$out/topics-configs.txt" | sort > "$out/retention.txt"
missing=$(awk '{ print $1 }' "$out/retention.txt" | sort | comm -13 - "$out/topics.txt" | tr '\n' ' ')
[ -z "$missing" ] || fail "no retention read for: $missing- the next dumps' guard could not judge them"
for r in $(awk '{ print $2 }' "$out/retention.txt" | sort -un); do
  [ "$r" -gt 0 ] || continue
  k=1
  while [ $((k * day)) -lt "$r" ] && [ "$k" -le 14 ]; do
    "$K/kafka-get-offsets.sh" --bootstrap-server "$BS" --topic '.*' --exclude-internal-topics --time $((now - r + k * day)) \
      > "$out/at.$r.$k" || fail "the offsets $k days into a retention of $r ms not read"
    k=$((k + 1))
  done
done
while read -r t r; do
  {
    echo "at:$now"
    echo "retention:$r"
    for f in "$out"/at."$r".*; do
      [ -f "$f" ] || continue
      awk -F: -v t="$t" -v x=$((now - r + ${f##*.} * day)) '$1 == t && $3 ~ /^[0-9]+$/ { print x ":" $2 ":" $3 }' "$f"
    done
  } > "$out/topics/$t.kept"
done < "$out/retention.txt"
rm -f "$out"/at.*
total=0
while read -r t; do
  [ -n "$t" ] || continue
  parts=$(awk -v t="$t" '$1 == "Topic:" && $2 == t { for (i = 1; i < NF; i++) if ($i == "PartitionCount:") print $(i + 1) }' \
    "$out/topics-describe.txt" | head -1)
  echo "$parts" | grep -qE '^[1-9][0-9]*$' || fail "$t: no partition count in its description"
  "$K/kafka-get-offsets.sh" --bootstrap-server "$BS" --topic "$t" --time -2 | sort -t: -k2,2n > "$out/topics/$t.earliest"
  "$K/kafka-get-offsets.sh" --bootstrap-server "$BS" --topic "$t" --time -1 | sort -t: -k2,2n > "$out/topics/$t.latest"
  # every partition, each with a numeric offset, in both readings (get-offsets skips a partition it cannot list - offline,
  # no leader - and exits 0)
  for f in earliest latest; do
    want=$(seq 0 $((parts - 1)) | tr '\n' ' ')
    got=$(awk -F: '$3 ~ /^[0-9]+$/ { print $2 }' "$out/topics/$t.$f" | tr '\n' ' ')
    [ "$got" = "$want" ] || fail "$t: the $f offsets name partitions '$got', its $parts partitions are '$want'"
  done
  while IFS=: read -r _ p first; do
    last=$(awk -F: -v p="$p" '$2 == p { print $3 }' "$out/topics/$t.latest")
    [ -n "$last" ] || fail "$t[$p]: no latest offset"
    n=$((last - first))
    [ "$n" -ge 0 ] || fail "$t[$p]: its latest offset $last before its earliest $first"
    [ "$n" -gt 0 ] || continue
    m="$out/topics/$t.$p.messages"
    "$K/kafka-console-consumer.sh" --bootstrap-server "$BS" --topic "$t" --partition "$p" --offset "$first" \
      --max-messages "$n" --timeout-ms 60000 --command-property auto.offset.reset=none \
      --formatter-property print.headers=true --formatter-property print.key=true \
      --formatter-property key.separator=$'\t' --formatter-property headers.separator=$'\x1e' \
      --formatter-property null.literal=__NULL__ \
      > "$m" 2> "$out/topics/$t.$p.log" \
      || { cat "$out/topics/$t.$p.log"; fail "$t[$p]: the read failed"; }
    got=$(wc -l < "$m")
    # the first line not a message named by its number and length - its text only when it is a Kafka tool's own notice
    # (a value's fragment, split at a raw newline, is a user's message: never into the logs); the consumer's own stderr
    # shown (a timeout or an error it exits 0 on - no message text in it)
    [ "$got" -eq "$n" ] || { cat "$out/topics/$t.$p.log"; fail "$t[$p]: $got messages read, its offsets say $n$(awk -F '\t' 'NF < 3 {
      printf "; not a message: line %d (%d characters)", NR, length($0)
      if ($0 ~ /^(Option |Warning: )--[a-z.-]+ is deprecated/) printf ": %.160s", $0
      exit }' "$m")"; }
    ! grep -q $'\r' "$m" || fail "$t[$p]: a carriage return in a message - the producer's line reader would split it"
    iconv -f UTF-8 -t UTF-8 < "$m" | cmp -s - "$m" || fail "$t[$p]: a message not valid UTF-8 - it would not come back as it was"
    short=$(awk -F '\t' 'NF < 3' "$m" | wc -l)
    [ "$short" -eq 0 ] || fail "$t[$p]: $short lines with fewer than three fields (headers, key, value)"
    rm -f "$out/topics/$t.$p.log"
    total=$((total + n))
  done < "$out/topics/$t.earliest"
done < "$out/topics.txt"
# a restore begun while this read (its ConfigMap mounted since): this dump read a Kafka being filled - no DONE
[ ! -e "$RESTORING" ] || fail "a restore began while dumping (since $(cat "$RESTORING")) - no DONE"
echo "$ts $(wc -l < "$out/topics.txt") topics $total messages" > "$out/DONE"
cat "$out/DONE"
