#!/bin/sh
# Before a Kafka dump ($1, kafka-backup-dump.sh's directory) goes to the Pi store: does Kafka still hold everything the
# store's dumps held? A topic gone, a topic made again (its TopicId changed - Strimzi's topic operator makes a lost
# topic again, empty), a partition gone or its latest offset lower than a dump's, or its earliest offset past what the
# dump's retention keeps (a retention cut short, records deleted, a clock stepped forward - the TopicId and the latest
# offsets stay): Kafka lost data, and this dump - uploaded, then the prune - would push the dumps that hold it out of the
# store within KEEP nights. Refused: nothing uploaded, nothing pruned, the Job failed (KubeJobFailed at once,
# KafkaBackupMissed after a day) - the dumps stay until a restore.
# The reference: the newest complete dump older than this one. A topic the store's BASELINE covers is judged against it
# only when that dump was made since the BASELINE (else not at all). BASELINE: a UTC timestamp, then "why <text>" and
# the topics it covers, "topic <name>" a line, or "all" (a timestamp alone: all). Ops' restore writes it for the topics
# it restored; ops' task deploy:kafka-backup-baseline for a topic removed on purpose. Every other topic is judged: a
# restore of one topic never hides another's loss. Timestamps are compared as numbers - the dumps' and the BASELINE's
# from the cluster's clock (one node; across nodes, NTP's skew of seconds against dumps a day apart).
# The retention check: the reference's topics/<topic>.kept (its retention then, and per partition its first offset at
# each checkpoint time) - the messages younger than now - that retention (an hour's margin) must still be in Kafka: the
# new earliest offset may not pass the reference's offset at the first checkpoint at or after that time (none: its latest
# - the messages since it). The reference's retention, not today's: a retention cut short is the loss. A reference with
# no record, or older than its retention lets judge, is said, not judged.
# A store listing or read that fails stops it, and so does a TopicId it cannot read (never "nothing to compare"). Nothing
# to judge (every topic covered, the reference older than the BASELINE): the reference's files are never read - a damaged
# one blocks nothing the BASELINE excused. STORE: rclone's remote/bucket.
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
ref=""
for n in $(printf '%s\n' "$dirs" | sed 's#/$##' | grep -E '^[0-9]{8}T[0-9]{6}Z$' | sort -r); do
  [ "$(ts "$n")" -lt "$(ts "$d")" ] || continue  # this one, or one begun after it (a dump made by hand beside the night's)
  files=$(rclone lsf --files-only --max-depth 1 "$STORE/$n/") || fail "listing $STORE/$n failed: not uploaded"
  printf '%s\n' "$files" | grep -qxF DONE || continue
  ref=$n
  break
done
if [ -z "$ref" ]; then echo "no complete dump before this one to compare with"; exit 0; fi
fresh=""  # the reference made since the BASELINE: the topics it covers judged against it too
if [ -n "$base" ] && [ "$(ts "$ref")" -gt "$(ts "$base")" ]; then fresh=1; fi
if [ "$covers" = '*' ] && [ -z "$fresh" ]; then
  echo "Kafka holds everything its dumps held: nothing to compare (the BASELINE of $base covers every topic, $ref older)"
  exit 0
fi
w=$(mktemp -d)
trap 'rm -rf "$w"' EXIT
rclone copy "$STORE/$ref" "$w" --include topics.txt --include topics-describe.txt --include 'topics/*.latest' \
  --include 'topics/*.earliest' --include 'topics/*.kept' || fail "reading $ref's offsets failed: not uploaded"
[ -s "$w/topics.txt" ] || fail "$ref holds no topics.txt: not uploaded (a damaged dump: ops' task deploy:kafka-backup-retire)"
id() {
  awk -v t="$1" '$1 == "Topic:" && $2 == t { for (i = 1; i < NF; i++) if ($i == "TopicId:") print $(i + 1) }' "$2" | head -1
}
# kept <topic>: a line "<partition> <earliest now> <the reference's bound>" for each partition whose messages the
# reference's retention keeps are gone; "unjudged <why>" when it cannot tell
kept() {
  now=$(sed -n 's/^at://p' "$new/topics/$1.kept" 2> /dev/null)
  [ -n "$now" ] || now=$(( $(date +%s) * 1000 ))
  [ -f "$w/topics/$1.kept" ] || { echo "unjudged no retention record"; return 0; }
  awk -F: -v now="$now" -v margin=3600000 '
    FILENAME == ARGV[1] { if ($1 == "at") at = $2 + 0; else if ($1 == "retention") r = $2 + 0
                          else if (NF == 3) { if (!(($1 + 0) in seen)) { seen[$1 + 0] = 1; xs[++nx] = $1 + 0 }; off[$1 + 0, $2] = $3 + 0 }
                          next }
    FILENAME == ARGV[2] { last[$2] = $3 + 0; next }
    FILENAME == ARGV[3] { first[$2] = $3 + 0; next }
    FILENAME == ARGV[4] { now_first[$2] = $3 + 0; next }
    END {
      if (at == "" || r == "") { print "unjudged its retention record unreadable"; exit }
      if (r < 0) { for (p in last) if ((p in now_first) && (p in first) && now_first[p] > first[p]) print p, now_first[p], first[p]; exit }
      need = now - r + margin
      if (need > at) { print "unjudged older than its retention lets judge"; exit }
      x = ""; for (i = 1; i <= nx; i++) if (xs[i] >= need && (x == "" || xs[i] < x)) x = xs[i]
      for (p in last) {
        bound = (x != "" && ((x, p) in off)) ? off[x, p] : last[p]
        if ((p in now_first) && now_first[p] > bound) print p, now_first[p], bound
      }
    }' "$w/topics/$1.kept" "$w/topics/$1.latest" "$w/topics/$1.earliest" "$new/topics/$1.earliest"
}
lost="" judged="" unjudged=""
while read -r t; do
  [ -n "$t" ] || continue
  if covered "$t" && [ -z "$fresh" ]; then continue; fi  # covered, nothing since the BASELINE to compare with
  judged="$judged $t@$ref"
  if ! grep -qxF "$t" "$new/topics.txt"; then lost="$lost; $t gone (since $ref)"; continue; fi
  was=$(id "$t" "$w/topics-describe.txt"); now_id=$(id "$t" "$new/topics-describe.txt")
  [ -n "$was" ] && [ -n "$now_id" ] || fail "no TopicId for $t ($ref: '$was', now: '$now_id') - the describe format changed? not uploaded"
  if [ "$was" != "$now_id" ]; then lost="$lost; $t made again (TopicId $was -> $now_id, since $ref)"; continue; fi
  [ -f "$w/topics/$t.latest" ] && [ -f "$w/topics/$t.earliest" ] \
    || fail "$ref holds no offsets for $t: not uploaded (a damaged dump: ops' task deploy:kafka-backup-retire)"
  while IFS=: read -r _ p o; do
    o2=$(awk -F: -v p="$p" '$2 == p { print $3 }' "$new/topics/$t.latest")
    if [ -z "$o2" ]; then lost="$lost; $t[$p] gone (since $ref)"; elif [ "$o2" -lt "$o" ]; then lost="$lost; $t[$p] at $o2, was $o ($ref)"; fi
  done < "$w/topics/$t.latest"
  k=$(kept "$t")
  case "$k" in
    unjudged*) unjudged="$unjudged $t (${k#unjudged })" ;;
    *) while read -r p e bound; do
         [ -n "$p" ] || continue
         lost="$lost; $t[$p] begins at $e, $ref's retention keeps it from $bound"
       done << EOF_KEPT
$k
EOF_KEPT
       ;;
  esac
done < "$w/topics.txt"
[ -z "$lost" ] || fail "Kafka lost data:${lost#;} - not uploaded, nothing pruned (restore it: ops' tasks/kafka-restore.yml; a topic removed on purpose: task deploy:kafka-backup-baseline -- -e kafka_baseline_topics=<topic>)"
echo "Kafka holds everything its dumps held:${judged:- nothing to compare}${unjudged:+; retention not judged for$unjudged}"
