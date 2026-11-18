#!/bin/bash
# Kafka's topics dumped under $OUT/<UTC timestamp>/ (an emptyDir the upload then ships to the Pi store): the topics'
# descriptions, the consumer groups' committed offsets, and every message each partition holds - read from its earliest
# offset, exactly as many as its offsets say (latest - earliest, fixed before the read: a message written meanwhile is
# the next night's), each line its headers, key and value (tab-separated; headers apart by 0x1e - Spring's JSON type
# header holds commas; a header's key and value by the formatter's fixed ':', the producer splitting at the first one - no
# header key holds one; NO_HEADERS for none). DONE written last. Refused, no DONE (a dump that would not restore as it was
# is no dump):
#   - no topic at all (a Kafka that lost its data would otherwise prune every good dump away within a week)
#   - a partition missing from the offsets read (every partition 0..PartitionCount-1, from the topic's description)
#   - a read not of its offsets' count (one message per line: a value holding a newline breaks it; a tool's notice on
#     stdout adds a line - Kafka 4.3's console consumer prints one there for a deprecated option)
#   - a carriage return, a line not valid UTF-8, or one with fewer than three fields (the producer's line reader would
#     split, mangle or misparse it)
# The read never jumps: auto.offset.reset=none - retention moving the log start past the first offset is an error, not
# a silent reset to the log's end. Given as --command-property (Kafka 4.3: --consumer-property is deprecated, and its
# notice goes to stdout - among the messages).
set -euo pipefail
K=${KAFKA_BIN:-/opt/kafka/bin}
BS=${BOOTSTRAP:?}
ts=$(date -u +%Y%m%dT%H%M%SZ)
out=${OUT:?}/$ts
mkdir -p "$out/topics"
fail() { echo "$*"; exit 1; }
"$K/kafka-topics.sh" --bootstrap-server "$BS" --list --exclude-internal | sort > "$out/topics.txt"
[ -s "$out/topics.txt" ] || fail "no topic in Kafka - nothing dumped (a dump of nothing would prune the good ones away)"
"$K/kafka-topics.sh" --bootstrap-server "$BS" --describe --exclude-internal > "$out/topics-describe.txt"
"$K/kafka-consumer-groups.sh" --bootstrap-server "$BS" --describe --all-groups --offsets > "$out/groups.txt" 2>&1 \
  || { cat "$out/groups.txt"; fail "the consumer groups' offsets not read"; }
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
    [ "$got" -eq "$n" ] || fail "$t[$p]: $got messages read, its offsets say $n$(awk -F '\t' 'NF < 3 { printf "; not a message: %.160s", $0; exit }' "$m")"
    ! grep -q $'\r' "$m" || fail "$t[$p]: a carriage return in a message - the producer's line reader would split it"
    iconv -f UTF-8 -t UTF-8 < "$m" | cmp -s - "$m" || fail "$t[$p]: a message not valid UTF-8 - it would not come back as it was"
    short=$(awk -F '\t' 'NF < 3' "$m" | wc -l)
    [ "$short" -eq 0 ] || fail "$t[$p]: $short lines with fewer than three fields (headers, key, value)"
    rm -f "$out/topics/$t.$p.log"
    total=$((total + n))
  done < "$out/topics/$t.earliest"
done < "$out/topics.txt"
echo "$ts $(wc -l < "$out/topics.txt") topics $total messages" > "$out/DONE"
cat "$out/DONE"
