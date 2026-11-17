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
# CNPG's CRD wants a positive count ("0d" refused at apply)
check "the Cluster's store keeps a window (spec.backup.retentionPolicy)" "$(echo "$retention" | grep -cE '^[1-9][0-9]*[dwm]$')" 1
# SonarQube's own CNPG cluster (schnappy-sonarqube, 2026-11-17) the same: once a day, a bounded window - and its backups
# under a name of their own in the store (CNPG archives only into an empty one; production's is never shared)
sq=$(helm template t helm/schnappy-sonarqube/ --namespace schnappy-infra --set sonarqube.enabled=true --set sonarqube.existingSecret=sq --set vault.secretsEnabled=true \
  --set sonarqube.cnpg.enabled=true --set sonarqube.cnpg.backup=true --set sonarqube.cnpg.backupEndpoint=http://store:9000 \
  --set sonarqube.cnpg.backupServerName=schnappy-sonarqube-pg18)
sq_schedule=$(printf '%s\n' "$sq" | awk '/^kind: ScheduledBackup/ { s = 1 } s && /^  schedule:/ { gsub(/"/, ""); sub(/^  schedule: /, ""); print; exit }')
check "SonarQube's: once a day, CNPG's six fields" \
  "$(echo "$sq_schedule" | awk '{ print (NF == 6 && $1 ~ /^[0-9]+$/ && $2 ~ /^[0-9]+$/ && $3 ~ /^[0-9]+$/ && $4 $5 $6 == "***") }')" 1
check "SonarQube's: a bounded window" \
  "$(printf '%s\n' "$sq" | awk '/^kind: Cluster/ { c = 1 } c && /^    retentionPolicy:/ { gsub(/"/, ""); print $2; exit }' | grep -cE '^[1-9][0-9]*[dwm]$')" 1
check "SonarQube's: its first base backup at once (immediate), not the next night" \
  "$(printf '%s\n' "$sq" | awk '/^kind: ScheduledBackup/ { s = 1 } s && /^  immediate:/ { print $2; exit }')" true
# refused renders: the chart's own guards (each a fail with its reason - never a render that ships)
sqr() { helm template t helm/schnappy-sonarqube/ --namespace schnappy-infra --set sonarqube.enabled=true --set sonarqube.existingSecret=sq \
  --set vault.secretsEnabled=true --set sonarqube.cnpg.enabled=true --set sonarqube.cnpg.backupEndpoint=http://store:9000 "$@" 2>&1; }
# the store's name: its own, never production's (the Pis' restore check restores that one) and never none
check "SonarQube's backups under production's server name: refused" \
  "$(sqr --set sonarqube.cnpg.backup=true --set sonarqube.cnpg.backupServerName=schnappy-production-postgres-pg18 | grep -c 'execution error.*restore check reads that one')" 1
check "SonarQube's backups without a server name: refused" \
  "$(sqr --set sonarqube.cnpg.backup=true | grep -c 'execution error.*needs backupServerName')" 1
# the move's stages: SonarQube at 0 renders no setup Job (it would wait 40 minutes for the API and fail the sync)
check "SonarQube at replicas 0: its Deployment at 0, no setup Job" \
  "$(sqr --set sonarqube.replicas=0 | awk '/^kind: Deployment/ { d = 1 } d && /^  replicas:/ { print $2; d = 0 }') $(sqr --set sonarqube.replicas=0 | grep -c '^kind: Job$')" "0 0"
check "  at 1: the setup Job there" "$(sqr | grep -c '^kind: Job$')" 1
check "SonarQube on the StatefulSet with its pods at 0: refused" \
  "$(sqr --set sonarqube.postgresReplicas=0 | grep -c 'execution error.*statefulset needs sonarqube.postgresReplicas')" 1
check "the import with the StatefulSet's pods at 0: refused" \
  "$(sqr --set sonarqube.database=cnpg --set sonarqube.postgresReplicas=0 --set sonarqube.cnpg.import=true | grep -c 'execution error.*import reads the StatefulSet')" 1
check "import and recovery both: refused" \
  "$(sqr --set sonarqube.cnpg.import=true --set sonarqube.cnpg.recovery=true --set sonarqube.cnpg.recoveryServerName=a | grep -c 'execution error.*import or recovery')" 1
check "recovery into the server name it recovers from: refused" \
  "$(sqr --set sonarqube.cnpg.recovery=true --set sonarqube.cnpg.recoveryServerName=s1 --set sonarqube.cnpg.backup=true --set sonarqube.cnpg.backupServerName=s1 | grep -c 'execution error.*a new backupServerName')" 1
check "recovery: from barman (backup-source, the old name), its store keys there, the new name archived into" \
  "$(sqr --set sonarqube.cnpg.recovery=true --set sonarqube.cnpg.recoveryServerName=s1 --set sonarqube.cnpg.backup=true --set sonarqube.cnpg.backupServerName=s2 \
    | awk '/^kind: Cluster/ { c = 1 } /^---/ { c = 0 } c && /source: backup-source|serverName:/ { gsub(/^ +/, ""); printf "%s;", $0 }')" \
  "source: backup-source;serverName: s1;serverName: s2;"
[ "$fails" -eq 0 ] && echo "cnpg-backup-render: ALL-PASS" || { echo "cnpg-backup-render: $fails FAILED"; exit 1; }
