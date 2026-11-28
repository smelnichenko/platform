#!/bin/sh
# The backups' prune (files/backup-prune.sh - ClickHouse's and Kafka's CronJobs run it) with the real rclone, in the
# charts' own rcloneImage (the step's, checked against both values files), over a local remote: the newest KEEP complete
# backups kept, the older complete ones deleted (deletefile, then purge), a pinned one kept however old, a day-old
# incomplete one purged, a fresh one kept, a name not the jobs' untouched; an empty store - rclone's "directory not
# found" (exit 3, an assumption the stub test only writes down) - removes nothing and passes. The prune's delete path
# runs only past KEEP backups, which the copy's store never holds: first exercised here, not on production's night 8
# (the wave-patches review, 2026-11-28: rclone 1.71.2 -> 1.76.0)
set -eu
for v in helm/schnappy-observability/values.yaml helm/schnappy-data/values.yaml; do
  chart=$(sed -n 's/^ *rcloneImage: *//p' "$v")
  [ -n "${CI_STEP_IMAGE_CHECK:-}" ] && [ "$CI_STEP_IMAGE_CHECK" = "$chart" ] \
    || { echo "FAIL the step's image (${CI_STEP_IMAGE_CHECK:-unset}) is not $v's rcloneImage ($chart)"; exit 1; }
done
script=$PWD/helm/schnappy-observability/files/backup-prune.sh
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
export RCLONE_CONFIG_STORE_TYPE=local
stamp() { date -u -d "@$(($(date +%s) - $1))" +%Y%m%dT%H%M%SZ; }  # $1 seconds ago
complete=""
for d in 9 8 7 6 5 4 3 2 1; do  # nine complete, a day apart (the oldest nine days old)
  n=$(stamp $((d * 86400 + 3600)))
  mkdir -p "$W/bucket/logs/$n/data"
  echo x > "$W/bucket/logs/$n/.backup"; echo x > "$W/bucket/logs/$n/data/part"
  complete="$complete $n"
done
pinned=$(stamp $((12 * 86400)))
mkdir -p "$W/bucket/logs/$pinned"; echo x > "$W/bucket/logs/$pinned/.backup"; echo x > "$W/bucket/logs/$pinned/PINNED"
old_incomplete=$(stamp $((2 * 86400)))
mkdir -p "$W/bucket/logs/$old_incomplete"; echo x > "$W/bucket/logs/$old_incomplete/part"
fresh_incomplete=$(stamp 600)
mkdir -p "$W/bucket/logs/$fresh_incomplete"; echo x > "$W/bucket/logs/$fresh_incomplete/part"
mkdir -p "$W/bucket/logs/not-a-backup"; echo x > "$W/bucket/logs/not-a-backup/f"
out=$(STORE="store:$W/bucket" PREFIX=logs/ KEEP=7 MARKER=.backup sh "$script" 2>&1) || { echo "FAIL the prune failed:"; echo "$out"; exit 1; }
left=$(ls "$W/bucket/logs" | sort | tr '\n' ' ')
oldest2=$(echo $complete | cut -d' ' -f1-2)
kept7=$(echo $complete | cut -d' ' -f3-9)
fails=0
check() { if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1: got '$2', want '$3'"; fails=$((fails + 1)); fi; }
check "the two oldest complete backups deleted, the newest seven kept" \
  "$(for n in $oldest2; do [ -e "$W/bucket/logs/$n" ] && echo "$n left"; done)$(for n in $kept7; do [ -e "$W/bucket/logs/$n/.backup" ] || echo "$n gone"; done)" ""
check "  a pinned backup kept however old; a day-old incomplete one purged; a fresh one and a name not the jobs' kept" \
  "$([ -e "$W/bucket/logs/$pinned/.backup" ] && echo pinned) $([ -e "$W/bucket/logs/$old_incomplete" ] || echo purged) $([ -e "$W/bucket/logs/$fresh_incomplete" ] && echo fresh) $([ -e "$W/bucket/logs/not-a-backup" ] && echo other)" \
  "pinned purged fresh other"
check "  said: 10 complete (the pinned one counted), 3 removed" "$(echo "$out" | tail -1)" \
  "backups in store:$W/bucket/logs/: 10 complete, 3 removed, the newest 7 complete kept"
# an empty store: its folder made, the listing's "directory not found" no failure - nothing removed
out=$(STORE="store:$W/empty" PREFIX=logs/ KEEP=7 MARKER=.backup sh "$script" 2>&1) || { echo "FAIL the prune on an empty store failed:"; echo "$out"; fails=$((fails + 1)); }
check "an empty store (rclone's directory not found): passes, nothing removed" "$(echo "$out" | tail -1)" \
  "backups in store:$W/empty/logs/: 0 complete, 0 removed, the newest 7 complete kept"
[ "$fails" = 0 ] || { echo "$left"; exit 1; }
echo "PASS the backups' prune with the real rclone ($(rclone version | head -1))"
