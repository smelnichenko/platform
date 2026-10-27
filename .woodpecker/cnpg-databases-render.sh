#!/bin/sh
# A service database's extensions as schnappy-data renders them: an entry with extensions and its owner is a CNPG
# Database keeping them present (retain: never dropped with the resource); one without extensions renders none; one
# with extensions but no owner is refused - CNPG would ALTER the database to whatever owner it is given. masi's pgvector
# was created by hand in production and missing in test (masi crash-looped three days, 2026-10-24..27).
set -eu
base="--namespace schnappy-test --set postgres.password=test --set cnpg.enabled=true"
fails=0
check() { if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1: got '$2', want '$3'"; fails=$((fails + 1)); fi; }
# shellcheck disable=SC2086
out=$(helm template t helm/schnappy-data/ $base --set 'postgres.databases[0].name=chat' \
  --set 'postgres.databases[1].name=masi' --set 'postgres.databases[1].owner=masi' --set 'postgres.databases[1].extensions[0]=vector')
db=$(printf '%s\n' "$out" | awk '/^kind: Database$/ { d = 1 } d && /^spec:/ { s = 1 } d && s')
check "one Database: masi's, not chat's (no extensions)" "$(printf '%s\n' "$out" | grep -c '^kind: Database$')" 1
check "  its database, owner and reclaim policy" \
  "$(printf '%s\n' "$db" | grep -E '^  (name|owner|databaseReclaimPolicy|ensure):' | tr -s ' ' | tr '\n' ' ')" \
  " name: masi  owner: masi  ensure: present  databaseReclaimPolicy: retain "
check "  vector kept present" "$(printf '%s\n' "$db" | grep -A1 -- '- name: vector' | grep -c 'ensure: present')" 1
# shellcheck disable=SC2086
check "extensions without an owner: refused" \
  "$(helm template t helm/schnappy-data/ $base --set 'postgres.databases[0].name=masi' \
     --set 'postgres.databases[0].extensions[0]=vector' 2>&1 | grep -c 'extensions need its owner')" 1
[ "$fails" -eq 0 ] && echo "cnpg-databases-render: ALL-PASS" || { echo "cnpg-databases-render: $fails FAILED"; exit 1; }
