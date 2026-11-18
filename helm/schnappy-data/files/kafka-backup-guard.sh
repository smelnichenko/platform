#!/bin/sh
# Before a Kafka dump ($1, kafka-backup-dump.sh's directory) goes to the Pi store: does Kafka still hold everything the
# store's dumps held? A topic gone, a topic made again (its TopicId changed - Strimzi's topic operator makes a lost
# topic again, empty), a partition gone or its latest offset lower than a dump's: Kafka lost data, and this dump -
# uploaded, then the prune - would push the dumps that hold it out of the store within KEEP nights. Refused: nothing
# uploaded, nothing pruned, the Job failed (KafkaBackupMissed) - the dumps stay until a restore.
# Each topic compared with the newest complete dump older than this one - unless the store's BASELINE covers it: then
# with the newest complete dump since the BASELINE (none: not compared). BASELINE: a UTC timestamp, then "why <text>"
# and the topics it covers, "topic <name>" a line, or "all" (a timestamp alone: all). A restore writes it for the
# topics it restored; ops' task deploy:kafka-backup-baseline for a topic removed on purpose. Every other topic is still
# compared with the newest dump before it: a restore of one topic never hides another's loss. A store listing or read
# that fails stops it, and so does a TopicId it cannot read (never "nothing to compare"). STORE: rclone's remote/bucket.
set -eu
new=${1:?the new dump directory}
d=$(basename "$new")
fail() { echo "$*"; exit 1; }
ts() { echo "$1" | tr -d TZ; }
top=$(rclone lsf --files-only --max-depth 1 "$STORE/") || fail "listing $STORE failed: not uploaded"
base="" covers=""
if printf '%s\n' "$top" | grep -qxF BASELINE; then
  b=$(rclone cat "$STORE/BASELINE") || fail "reading $STORE/BASELINE failed: not uploaded"
  base=$(printf '%s\n' "$b" | head -1)
  printf '%s\n' "$base" | grep -qE '^[0-9]{8}T[0-9]{6}Z$' || fail "$STORE/BASELINE holds no timestamp ('$base'): not uploaded"
  covers=$(printf '%s\n' "$b" | sed -n 's/^topic //p')
  if printf '%s\n' "$b" | grep -qx all || [ -z "$covers" ]; then covers='*'; fi
fi
covered() { [ -n "$base" ] && { [ "$covers" = '*' ] || printf '%s\n' "$covers" | grep -qxF "$1"; }; }
dirs=$(rclone lsf --dirs-only "$STORE/") || fail "listing $STORE failed: not uploaded"
before="" since=""  # the newest complete dump older than this one; the newest of those since the BASELINE
for n in $(printf '%s\n' "$dirs" | sed 's#/$##' | grep -E '^[0-9]{8}T[0-9]{6}Z$' | sort -r || true); do
  [ "$(ts "$n")" -lt "$(ts "$d")" ] || continue  # this one, or one begun after it (a dump made by hand beside the night's)
  files=$(rclone lsf --files-only --max-depth 1 "$STORE/$n/") || fail "listing $STORE/$n failed: not uploaded"
  printf '%s\n' "$files" | grep -qxF DONE || continue
  before=$n
  # since the BASELINE: the same dump when it is newer than the BASELINE; else none
  if [ -n "$base" ] && [ "$(ts "$n")" -gt "$(ts "$base")" ]; then since=$n; fi
  break
done
if [ -z "$before" ]; then echo "no complete dump before this one to compare with"; exit 0; fi
w=$(mktemp -d)
trap 'rm -rf "$w"' EXIT
fetch() {  # fetch <dump>: its topics, their descriptions and latest offsets, into $w/<dump>
  [ -d "$w/$1" ] && return 0
  rclone copy "$STORE/$1" "$w/$1" --include topics.txt --include topics-describe.txt --include 'topics/*.latest' \
    || fail "reading $1's offsets failed: not uploaded"
  [ -s "$w/$1/topics.txt" ] || fail "$1 holds no topics.txt: not uploaded"
}
id() {
  awk -v t="$1" '$1 == "Topic:" && $2 == t { for (i = 1; i < NF; i++) if ($i == "TopicId:") print $(i + 1) }' "$2" | head -1
}
fetch "$before"
[ -z "$since" ] || fetch "$since"
lost="" judged=""
while read -r t; do
  [ -n "$t" ] || continue
  ref=$before
  if covered "$t"; then
    ref=$since
    [ -n "$ref" ] && grep -qxF "$t" "$w/$ref/topics.txt" || continue  # covered, nothing since to compare with
  fi
  judged="$judged $t@$ref"
  if ! grep -qxF "$t" "$new/topics.txt"; then lost="$lost; $t gone (since $ref)"; continue; fi
  was=$(id "$t" "$w/$ref/topics-describe.txt"); now=$(id "$t" "$new/topics-describe.txt")
  [ -n "$was" ] && [ -n "$now" ] || fail "no TopicId for $t ($ref: '$was', now: '$now') - the describe format changed? not uploaded"
  [ "$was" = "$now" ] || lost="$lost; $t made again (TopicId $was -> $now, since $ref)"
  [ -f "$w/$ref/topics/$t.latest" ] || fail "$ref holds no offsets for $t: not uploaded"
  while IFS=: read -r _ p o; do
    o2=$(awk -F: -v p="$p" '$2 == p { print $3 }' "$new/topics/$t.latest")
    if [ -z "$o2" ]; then lost="$lost; $t[$p] gone (since $ref)"; elif [ "$o2" -lt "$o" ]; then lost="$lost; $t[$p] at $o2, was $o ($ref)"; fi
  done < "$w/$ref/topics/$t.latest"
done < "$w/$before/topics.txt"
[ -z "$lost" ] || fail "Kafka lost data:${lost#;} - not uploaded, nothing pruned (restore it: ops' tasks/kafka-restore.yml; a topic removed on purpose: task deploy:kafka-backup-baseline -- -e kafka_baseline_topics=<topic>)"
echo "Kafka holds everything its dumps held:${judged:- nothing to compare}"
