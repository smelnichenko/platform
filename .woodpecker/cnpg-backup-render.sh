#!/bin/sh
# The CNPG backups as schnappy-data renders them for production: the ScheduledBackup runs once a day - CNPG's schedule
# has a seconds field first, so the 5-field "30 1 * * *" ran at second 30 of minute 1 of EVERY hour (production: an
# hourly base backup from 2026-04 to 2026-10, thousands of them) - and the Cluster's store keeps a bounded window.
set -eu
out=$(helm template t helm/schnappy-data/ --namespace schnappy-production --set postgres.password=test \
  --set cnpg.enabled=true --set cnpg.backup=true --set cnpg.backupEndpoint=http://store:9000 \
  --set cnpg.backupSecret=store-secret)
fails=0
check() { if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1: got '$2', want '$3'"; fails=$((fails + 1)); fi; }
schedule=$(printf '%s\n' "$out" | awk '/^kind: ScheduledBackup/ { s = 1 } s && /^  schedule:/ { gsub(/"/, ""); sub(/^  schedule: /, ""); print; exit }')
# six fields, seconds and minutes and hours fixed, every day: once a day
check "the ScheduledBackup's schedule has CNPG's six fields" "$(echo "$schedule" | awk '{ print NF }')" 6
check "once a day: second, minute and hour fixed, every day of every month" \
  "$(echo "$schedule" | awk '{ print ($1 ~ /^[0-9]+$/ && $2 ~ /^[0-9]+$/ && $3 ~ /^[0-9]+$/ && $4 $5 $6 == "***") }')" 1
retention=$(printf '%s\n' "$out" | awk '/^kind: Cluster/ { c = 1 } c && /^    retentionPolicy:/ { gsub(/"/, ""); print $2; exit }')
check "the Cluster's store keeps a window (spec.backup.retentionPolicy)" "$(echo "$retention" | grep -cE '^[0-9]+[dwm]$')" 1
[ "$fails" -eq 0 ] && echo "cnpg-backup-render: ALL-PASS" || { echo "cnpg-backup-render: $fails FAILED"; exit 1; }
