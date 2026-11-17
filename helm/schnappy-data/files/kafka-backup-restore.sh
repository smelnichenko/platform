#!/bin/bash
# A Kafka dump (kafka-backup-dump.sh's directory, $1) produced back into its topics. Every topic restored must exist
# with the partitions it had (Strimzi's KafkaTopics make them) and hold nothing - or exactly the dump's messages already
# (a re-run after a failure goes on with the rest); anything else is refused (FORCE=1 produces anyway: duplicates). No
# consumer group may be live on a restored topic (a consumer would read a week of history again - stop the services
# first); after it, each group the dump names is moved to the topics' end (RESET_GROUPS=no leaves them) - the restored
# messages are history, already processed once. Each partition's messages go in their order (a keyed message on its
# partition again - the same key, the same count), synchronously; each topic's end offsets must have grown by exactly the
# dump's count. The console producer cannot take "no headers" in a line with a headers field: a run of header-less
# messages (NO_HEADERS) goes through a producer parsing none. TOPICS (space-separated) restores those alone.
set -euo pipefail
K=${KAFKA_BIN:-/opt/kafka/bin}
BS=${BOOTSTRAP:?}
dump=${1:?a dump directory}
fail() { echo "$*"; exit 1; }
[ -f "$dump/DONE" ] || fail "$dump: no DONE - an incomplete dump, not restored"
all=$(grep -v '^$' "$dump/topics.txt" | tr '\n' ' ')
if [ -n "${TOPICS:-}" ]; then
  for t in $TOPICS; do case " $all " in *" $t "*) ;; *) fail "$t: not in the dump $(basename "$dump")" ;; esac; done
  topics=$TOPICS
else
  topics=$all
fi
sum_end() { "$K/kafka-get-offsets.sh" --bootstrap-server "$BS" --topic "$1" --time -1 | awk -F: '{ s += $3 } END { print s + 0 }'; }
held() {  # held <topic>: the messages it holds (latest - earliest, over its partitions)
  local e l
  e=$("$K/kafka-get-offsets.sh" --bootstrap-server "$BS" --topic "$1" --time -2 | awk -F: '{ s += $3 } END { print s + 0 }')
  l=$(sum_end "$1")
  echo $((l - e))
}
dumped() { cat "$dump/topics/$1".*.messages 2> /dev/null | wc -l; }
# every topic first: there, its partitions as dumped, empty (or done); no group live on it
todo=""
for t in $topics; do
  want=$(wc -l < "$dump/topics/$t.earliest")
  have=$({ "$K/kafka-topics.sh" --bootstrap-server "$BS" --describe --topic "$t" 2> /dev/null || true; } \
    | awk -v t="$t" '$1 == "Topic:" && $2 == t { for (i = 1; i < NF; i++) if ($i == "PartitionCount:") print $(i + 1) }' | head -1)
  [ -n "$have" ] || fail "$t: no such topic - make it first (its KafkaTopic), with its $want partitions"
  [ "$have" = "$want" ] || fail "$t: $have partitions, the dump's $want - a keyed message would land elsewhere"
  h=$(held "$t"); d=$(dumped "$t")
  if [ "$h" -eq 0 ]; then todo="$todo $t"
  elif [ "$h" -eq "$d" ]; then echo "$t: holds the dump's $d messages already - skipped"
  elif [ "${FORCE:-}" = 1 ]; then echo "$t: holds $h messages - FORCE: produced on top"; todo="$todo $t"
  else fail "$t: holds $h messages (the dump $d) - not restored into a topic in use (FORCE=1 duplicates)"
  fi
done
# the groups with offsets on these topics - now, or in the dump - each with no member (its --state's #MEMBERS, the last
# column: COORDINATOR (ID) holds a space)
groups=$({ "$K/kafka-consumer-groups.sh" --bootstrap-server "$BS" --describe --all-groups --offsets 2> /dev/null; cat "$dump/groups.txt"; } \
  | awk -v ts=" $topics " '$1 != "GROUP" && NF >= 3 && index(ts, " " $2 " ") { print $1 }' | sort -u)
live=""
for g in $groups; do
  m=$("$K/kafka-consumer-groups.sh" --bootstrap-server "$BS" --describe --group "$g" --state 2> /dev/null \
    | awk -v g="$g" '$1 == g { print $NF }' | head -1)
  [ "${m:-0}" = 0 ] || live="$live $g"
done
[ -z "$live" ] || fail "consumer groups live on the topics:$live - stop their services first"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
produce() {  # produce <topic> <file> <headers: yes|no>
  local h=(--reader-property parse.headers=false)
  [ "$3" = no ] || h=(--reader-property parse.headers=true --reader-property headers.delimiter=$'\t'
    --reader-property headers.separator=$'\x1e' --reader-property headers.key.separator=:)
  "$K/kafka-console-producer.sh" --bootstrap-server "$BS" --topic "$1" --sync --reader-property parse.key=true \
    --reader-property key.separator=$'\t' --reader-property null.marker=__NULL__ "${h[@]}" < "$2"
}
total=0
for t in $todo; do
  before=$(sum_end "$t"); n=0
  # its partitions as the dump read them (never a glob: chat.messages.* would take a topic chat.messages.DLT too)
  while IFS=: read -r _ p _; do
    f="$dump/topics/$t.$p.messages"
    [ -s "$f" ] || continue
    rm -f "$work"/*
    # consecutive runs: with headers (h) or none (n, the NO_HEADERS field dropped), in the partition's order
    awk -F '\t' -v d="$work" '{ k = ($1 == "NO_HEADERS") ? "n" : "h"
      if (k != prev) { if (out) close(out); run++; prev = k; out = sprintf("%s/%06d.%s", d, run, k) }
      if (k == "n") sub(/^NO_HEADERS\t/, ""); print > out } END { if (out) close(out) }' "$f"
    for r in "$work"/*; do
      case "$r" in *.n) produce "$t" "$r" no ;; *) produce "$t" "$r" yes ;; esac
    done
    n=$((n + $(wc -l < "$f")))
  done < "$dump/topics/$t.earliest"
  after=$(sum_end "$t")
  [ $((after - before)) -eq "$n" ] || fail "$t: its end offsets grew by $((after - before)), the dump's $n were produced"
  total=$((total + n))
done
if [ "${RESET_GROUPS:-yes}" != no ]; then
  for t in $topics; do
    for g in $(awk -v t="$t" '$2 == t { print $1 }' "$dump/groups.txt" | sort -u); do
      "$K/kafka-consumer-groups.sh" --bootstrap-server "$BS" --group "$g" --topic "$t" --reset-offsets --to-latest --execute > /dev/null
      echo "group $g on $t: at the end"
    done
  done
fi
echo "restored $total messages from $(basename "$dump")"
