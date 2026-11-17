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
# the review's (2026-11-17): a recovery is SonarQube's database, owner and Vault's password, and reaches the store
# without backups on; the import reads the password alone; the cluster's own component; Argo never deletes it
rec=$(sqr --set sonarqube.cnpg.recovery=true --set sonarqube.cnpg.recoveryServerName=s1)
check "recovery: database sonarqube, owner sonarqube, the -owner secret (no app role beside it)" \
  "$(printf '%s\n' "$rec" | awk '/^kind: Cluster/ { c = 1 } /^---/ { c = 0 } c && /^    recovery:/ { r = 1 } r && /^      (database|owner):|^        name:/ { gsub(/^ +/, ""); printf "%s;", $0 } c && /^  storage:/ { r = 0 }')" \
  "database: sonarqube;owner: sonarqube;name: t-schnappy-sonarqube-pg-owner;"
check "  and its pods reach the store with backups off (a drill)" \
  "$(printf '%s\n' "$rec" | awk '/^---/ { n = 0 } /^kind: NetworkPolicy/ { k = 1 } /^kind: / && !/NetworkPolicy/ { k = 0 } k && /^  name: t-schnappy-sonarqube-pg$/ { n = 1 } n && /port: 9000/ { c++ } END { print c + 0 }')" 1
imp=$(sqr --set sonarqube.cnpg.import=true)
check "the import reads the -owner secret's password - never SonarQube's secret (its admin password and token)" \
  "$(printf '%s\n' "$imp" | awk '/^kind: Cluster/ { c = 1 } /^---/ { c = 0 } c && /^      password:/ { p = 1; next } p { gsub(/^ +/, ""); printf "%s;", $0; if (++n == 2) exit }')" \
  "name: t-schnappy-sonarqube-pg-owner;key: password;"
check "the cluster's component its own (never the StatefulSet's sonarqube-postgres); Argo never prunes or deletes it" \
  "$(printf '%s\n' "$sq" | awk '/^kind: Cluster/ { c = 1 } /^---/ { c = 0 } c && /app.kubernetes.io\/component:|sync-options:/ { gsub(/^ +/, ""); printf "%s;", $0 }')" \
  "app.kubernetes.io/component: sonarqube-pg;argocd.argoproj.io/sync-options: Prune=false,Delete=false;"
# Grafana's own CNPG cluster (schnappy-observability, 2026-11-17): once a day, a bounded window, its first backup at
# once; its name in the store its own; Grafana's own network policy never selecting its pods
gfr() { helm template t helm/schnappy-observability/ --namespace schnappy-infra --set grafana.enabled=true --set grafana.existingSecret=gf --set vault.secretsEnabled=true \
  --set grafana.cnpg.enabled=true --set grafana.cnpg.backupEndpoint=http://store:9000 "$@" 2>&1; }
gf=$(gfr --set grafana.cnpg.backup=true --set grafana.cnpg.backupServerName=schnappy-grafana-pg18)
check "Grafana's: once a day, CNPG's six fields" \
  "$(printf '%s\n' "$gf" | awk '/^kind: ScheduledBackup/ { s = 1 } s && /^  schedule:/ { gsub(/"/, ""); sub(/^  schedule: /, ""); print; exit }' \
    | awk '{ print (NF == 6 && $1 ~ /^[0-9]+$/ && $2 ~ /^[0-9]+$/ && $3 ~ /^[0-9]+$/ && $4 $5 $6 == "***") }')" 1
check "Grafana's: a bounded window, its first base backup at once" \
  "$(printf '%s\n' "$gf" | awk '/^kind: Cluster/ { c = 1 } c && /^    retentionPolicy:/ { gsub(/"/, ""); print $2; exit }' | grep -cE '^[1-9][0-9]*[dwm]$') $(printf '%s\n' "$gf" | awk '/^kind: ScheduledBackup/ { s = 1 } s && /^  immediate:/ { print $2; exit }')" "1 true"
check "Grafana's backups under production's server name: refused" \
  "$(gfr --set grafana.cnpg.backup=true --set grafana.cnpg.backupServerName=schnappy-production-postgres-pg18 | grep -c 'execution error.*restore check reads that one')" 1
check "Grafana's backups without a server name: refused" \
  "$(gfr --set grafana.cnpg.backup=true | grep -c 'execution error.*needs backupServerName')" 1
check "Grafana on CNPG without its cluster: refused; a database neither sqlite nor cnpg: refused" \
  "$(gfr --set grafana.cnpg.enabled=false --set grafana.database=cnpg | grep -c 'execution error.*needs grafana.cnpg.enabled') $(gfr --set grafana.database=mysql | grep -c 'execution error.*sqlite or cnpg')" "1 1"
check "Grafana on CNPG: its database's host, user and password from CNPG's own secret, TLS" \
  "$(gfr --set grafana.database=cnpg | grep -A1 -E 'name: GF_DATABASE_(HOST|SSL_MODE)$' | grep -oE 'value: .*' | tr -d '"' | tr '\n' ';') $(gfr --set grafana.database=cnpg | grep -c 'name: t-schnappy-grafana-pg-app$')" \
  "value: t-schnappy-grafana-pg-rw:5432;value: require; 2"
check "  on sqlite (the default): no GF_DATABASE_ setting at all" "$(gfr | grep -c 'GF_DATABASE_')" 0
check "Grafana's cluster's labels: never Grafana's component (its network policy would select the database's pods)" \
  "$(printf '%s\n' "$gf" | awk '/^kind: Cluster/ { c = 1 } c && /app.kubernetes.io\/component:/ { print $2; exit }')" grafana-postgres
check "  Argo never prunes or deletes it" "$(printf '%s\n' "$gf" | awk '/^kind: Cluster/ { c = 1 } /^---/ { c = 0 } c && /sync-options:/ { print $2 }')" Prune=false,Delete=false
# the review's (2026-11-17): Grafana's probes outlive a migration and a Postgres restart; its connections under the
# mesh's idle cut; a recovery from its own backups (the store's keys and egress with backups off)
gdep=$(gfr --set grafana.database=cnpg | awk '/^kind: Deployment/ { d = 0 } /name: t-schnappy-grafana$/ { d = 1 } d')
check "Grafana: a startup probe (5 minutes), liveness the port alone, readiness /api/health; a 30-minute connection lifetime" \
  "$(printf '%s\n' "$gdep" | grep -A3 'startupProbe:' | grep -c 'path: /api/health') $(printf '%s\n' "$gdep" | grep -A1 'livenessProbe:' | grep -c tcpSocket) $(printf '%s\n' "$gdep" | grep -A1 'name: GF_DATABASE_CONN_MAX_LIFETIME' | grep -c '"1800"')" \
  "1 1 1"
grec=$(gfr --set grafana.cnpg.recovery=true --set grafana.cnpg.recoveryServerName=g1)
check "Grafana's recovery: from barman (g1), database and owner grafana, the store's keys rendered, its pods' egress to the store" \
  "$(printf '%s\n' "$grec" | awk '/^kind: Cluster/ { c = 1 } /^---/ { c = 0 } c && /source: backup-source|serverName: g1|database: grafana|owner: grafana/ { n++ } END { print n }') $(printf '%s\n' "$grec" | grep -c '^  name: t-schnappy-grafana-pg-backup-store$') $(printf '%s\n' "$grec" | awk '/^---/ { n = 0 } /^kind: NetworkPolicy/ { k = 1 } /^kind: / && !/NetworkPolicy/ { k = 0 } k && /^  name: t-schnappy-grafana-pg$/ { n = 1 } n && /port: 9000/ { c++ } END { print c + 0 }')" \
  "4 1 1"
check "  recovery into the server name it recovers from: refused; without one: refused" \
  "$(gfr --set grafana.cnpg.recovery=true --set grafana.cnpg.recoveryServerName=g1 --set grafana.cnpg.backup=true --set grafana.cnpg.backupServerName=g1 | grep -c 'execution error.*a new backupServerName') $(gfr --set grafana.cnpg.recovery=true | grep -c 'execution error.*needs recoveryServerName')" \
  "1 1"
[ "$fails" -eq 0 ] && echo "cnpg-backup-render: ALL-PASS" || { echo "cnpg-backup-render: $fails FAILED"; exit 1; }
