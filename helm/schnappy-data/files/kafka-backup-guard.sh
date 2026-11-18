#!/bin/sh
# Before a Kafka dump ($1, kafka-backup-dump.sh's directory) goes to the Pi store: does Kafka still hold everything the
# newest complete dump in the store held? A topic gone, a topic made again (its TopicId changed - Strimzi's topic
# operator makes a lost topic again, empty), a partition gone or its latest offset lower than that dump's: Kafka lost
# data, and this dump - uploaded, then the prune - would push the dumps that hold it out of the store within KEEP
# nights. Refused: nothing uploaded, nothing pruned, the Job failed (KafkaBackupMissed) - the dumps stay until a restore.
# A dump older than the store's BASELINE (a UTC timestamp; a restore writes it once Kafka is whole again, and so does
# task deploy:kafka-backup-baseline for a topic removed on purpose) is no comparison. A store listing or read that fails
# stops it too (never "nothing to compare"). STORE: rclone's remote and bucket.
set -eu
new=${1:?the new dump directory}
d=$(basename "$new")
fail() { echo "$*"; exit 1; }
top=$(rclone lsf --files-only --max-depth 1 "$STORE/") || fail "listing $STORE failed: not uploaded"
base=""
if printf '%s\n' "$top" | grep -qxF BASELINE; then
  base=$(rclone cat "$STORE/BASELINE") || fail "reading $STORE/BASELINE failed: not uploaded"
  base=$(printf '%s\n' "$base" | head -1)
  printf '%s\n' "$base" | grep -qE '^[0-9]{8}T[0-9]{6}Z$' || fail "$STORE/BASELINE holds no timestamp ('$base'): not uploaded"
fi
dirs=$(rclone lsf --dirs-only "$STORE/") || fail "listing $STORE failed: not uploaded"
prev=""
for n in $(printf '%s\n' "$dirs" | sed 's#/$##' | grep -E '^[0-9]{8}T[0-9]{6}Z$' | sort -r || true); do
  [ "$n" != "$d" ] || continue
  if [ -n "$base" ] && [ "$(echo "$n" | tr -d TZ)" -le "$(echo "$base" | tr -d TZ)" ]; then break; fi
  files=$(rclone lsf --files-only --max-depth 1 "$STORE/$n/") || fail "listing $STORE/$n failed: not uploaded"
  if printf '%s\n' "$files" | grep -qxF DONE; then prev=$n; break; fi
done
if [ -z "$prev" ]; then echo "no complete dump${base:+ since the baseline $base} to compare with"; exit 0; fi
w=$(mktemp -d)
trap 'rm -rf "$w"' EXIT
rclone copy "$STORE/$prev" "$w" --include topics.txt --include topics-describe.txt --include 'topics/*.latest' \
  || fail "reading $prev's offsets failed: not uploaded"
[ -s "$w/topics.txt" ] || fail "$prev holds no topics.txt: not uploaded"
id() { awk -v t="$1" '$1 == "Topic:" && $2 == t { for (i = 1; i < NF; i++) if ($i == "TopicId:") print $(i + 1) }' "$2" | head -1; }
lost=""
while read -r t; do
  [ -n "$t" ] || continue
  if ! grep -qxF "$t" "$new/topics.txt"; then lost="$lost; $t gone"; continue; fi
  was=$(id "$t" "$w/topics-describe.txt"); now=$(id "$t" "$new/topics-describe.txt")
  [ "$was" = "$now" ] || lost="$lost; $t made again (TopicId $was -> $now)"
  [ -f "$w/topics/$t.latest" ] || fail "$prev holds no offsets for $t: not uploaded"
  while IFS=: read -r _ p o; do
    o2=$(awk -F: -v p="$p" '$2 == p { print $3 }' "$new/topics/$t.latest")
    if [ -z "$o2" ]; then lost="$lost; $t[$p] gone"; elif [ "$o2" -lt "$o" ]; then lost="$lost; $t[$p] at $o2, was $o"; fi
  done < "$w/topics/$t.latest"
done < "$w/topics.txt"
[ -z "$lost" ] || fail "Kafka lost data since the dump $prev:${lost#;} - not uploaded, nothing pruned (restore it: ops' tasks/kafka-restore.yml; a topic removed on purpose: task deploy:kafka-backup-baseline)"
echo "Kafka holds everything the dump $prev held"
