#!/bin/sh
# Render checks for templates `helm lint` never sees: lint renders chart defaults, where the
# gateway routes, the LAN-only policy and its probe are all switched off.
set -eu

fail() { echo "FAIL: $*" >&2; exit 1; }

# --- schnappy-mesh: gatewayLanOnly ---------------------------------------------------------
mesh() { helm template t helm/schnappy-mesh/ --set gateway.enabled=true "$@"; }
lan='--set gatewayLanOnly.hosts={a.example} --set gatewayLanOnly.allowedCidrs={10.0.0.0/8}'

# shellcheck disable=SC2086
policy=$(mesh $lan --show-only templates/gateway-lan-only.yaml)
echo "$policy" | grep -q '^  action: DENY$' || fail "LAN-only policy is not a DENY"
echo "$policy" | grep -q '"a.example"$' || fail "LAN-only policy does not match the bare host"
echo "$policy" | grep -q '"a.example:\*"$' || fail "LAN-only policy does not match host:port"
echo "$policy" | grep -q '"10.0.0.0/8"$' || fail "LAN-only policy lost its allowed range"

# shellcheck disable=SC2086
gw=$(mesh $lan --show-only templates/gateway.yaml | awk '/^kind: Gateway$/ {g=1} g && /^  name:/ {print $2; exit}')
[ -n "$gw" ] || fail "no Gateway rendered"
echo "$policy" | grep -q "gateway-name: $gw\$" || fail "LAN-only policy does not select Gateway $gw"

err=$(mesh --set 'gatewayLanOnly.hosts={a.example}' 2>&1 >/dev/null) && fail "hosts without allowedCidrs rendered"
echo "$err" | grep -q 'gatewayLanOnly.allowedCidrs must list' || fail "unexpected error: $err"

# shellcheck disable=SC2086
err=$(helm template t helm/schnappy-mesh/ $lan --show-only templates/gateway-lan-only.yaml 2>&1 >/dev/null) \
  && fail "LAN-only policy rendered with the gateway disabled"
echo "$err" | grep -q 'could not find template' || fail "unexpected error: $err"

# --- schnappy-observability: Prometheus route ----------------------------------------------
obs() {
  helm template t helm/schnappy-observability/ --set gateway.enabled=true --set gateway.name=gw \
    --set gateway.namespace=ns --set gateway.hosts.prometheus=p.example "$@"
}
route=$(obs --set gateway.prometheusService=prom-svc --show-only templates/httproutes.yaml)
echo "$route" | grep -q 'name: prom-svc$' || fail "Prometheus route does not target the given Service"
echo "$route" | grep -q 'value: /-/quit }$' || fail "Prometheus route does not block /-/quit"
echo "$route" | grep -q 'value: /-/reload }$' || fail "Prometheus route does not block /-/reload"

err=$(obs 2>&1 >/dev/null) && fail "Prometheus host without prometheusService rendered"
echo "$err" | grep -q 'gateway.prometheusService is required' || fail "unexpected error: $err"

# --- schnappy-observability: LAN-only probe + alert ----------------------------------------
probe='--set prometheus.enabled=true --set alertmanager.enabled=true --set prometheus.lanOnlyProbeUrls={https://a.example/-/ready}'
# shellcheck disable=SC2086
monitors=$(helm template t helm/schnappy-observability/ $probe --show-only templates/infra-monitors.yaml)
echo "$monitors" | grep -q 'module: http_403_lan_only$' || fail "LAN-only Probe not rendered"
echo "$monitors" | grep -q -- '- https://a.example/-/ready$' || fail "LAN-only Probe lost its target"
# shellcheck disable=SC2086
helm template t helm/schnappy-observability/ $probe --show-only templates/blackbox-exporter.yaml \
  | grep -A6 'http_403_lan_only:' | grep -q 'valid_status_codes: \[403\]' || fail "blackbox module does not require 403"
# shellcheck disable=SC2086
helm template t helm/schnappy-observability/ $probe --show-only templates/prometheus-rules.yaml \
  | grep -q 'alert: LanOnlyHostReachable$' || fail "LanOnlyHostReachable rule not rendered"

# --- schnappy-data: Jobs are Argo Sync hooks; every postgres database is wired end to end ---
# Lint renders defaults, where cnpg and vault are off: the init-users Job and every
# ExternalSecret are invisible to it. Render them here.
data() { helm template t helm/schnappy-data/ --set postgres.password=test --set cnpg.enabled=true --set vault.secretsEnabled=true "$@"; }
rendered=$(data)

# A plain synced Job with a sync-wave is immutable once its template changes (a database added,
# an image bumped): Argo's patch fails and rolls the whole data sync back (s3gw-buckets
# 2026-06-29, init-users 2026-09-17). Such Jobs must be Sync hooks with BeforeHookCreation.
# `sync-options: Delete=true` is merely Argo's default (it guards nothing) and must not reappear.
jobs=$(echo "$rendered" | awk '
  function emit() { if (kind == "Job") print name "|" hook "|" del "|" wave "|" opts }
  /^---/ { emit(); kind = name = hook = del = wave = opts = ""; next }
  /^kind: / { kind = $2 }
  kind == "Job" && /^  name: / && name == "" { name = $2 }
  kind == "Job" && /^    argocd.argoproj.io\/hook: / { hook = $2 }
  kind == "Job" && /^    argocd.argoproj.io\/hook-delete-policy: / { del = $2 }
  kind == "Job" && /^    argocd.argoproj.io\/sync-wave: / { gsub(/"/, "", $2); wave = $2 }
  kind == "Job" && /^    argocd.argoproj.io\/sync-options: / { opts = $2 }
  END { emit() }')
[ -n "$jobs" ] || fail "schnappy-data rendered no Job"
for line in $jobs; do
  name=${line%%|*}; rest=${line#*|}; hook=${rest%%|*}; rest=${rest#*|}; del=${rest%%|*}; rest=${rest#*|}; wave=${rest%%|*}; opts=${rest#*|}
  [ -z "$opts" ] || fail "Job $name carries sync-options '$opts'; make it a Sync hook instead"
  [ "${wave:-0}" -lt 1 ] || [ "$hook" = "Sync" ] || fail "Job $name has sync-wave $wave but is not a Sync hook"
  [ "$hook" != "Sync" ] || [ "$del" = "BeforeHookCreation" ] || fail "hook Job $name lacks hook-delete-policy BeforeHookCreation"
done

# Every postgres.databases[].name must yield an ExternalSecret <fullname>-postgres-<db> reading
# <prefix>/postgres-<db> with DB_PASSWORD, and the init-users Job must consume THAT Secret
# for DB_PASSWORD_<DB> and carry the psql block that creates the role and database.
names=$(helm show values helm/schnappy-data/ | awk '
  /^postgres:/ { p = 1; next }  p && /^[^ ]/ { p = 0 }
  p && /^  databases:/ { d = 1; next }  p && d && /^  [^ ]/ { d = 0 }
  p && d && /^    - name: / { print $3 }')
[ -n "$names" ] || fail "postgres.databases is empty in schnappy-data values"
es=$(echo "$rendered" | awk '/^kind: ExternalSecret$/ { e = 1 } e && /^  name: / { print $2; e = 0 }')
init=$(echo "$rendered" | awk '/^# Source: schnappy-data\/templates\/cnpg-init-users.yaml/ { on = 1; next } /^---/ { on = 0 } on')
[ -n "$init" ] || fail "init-users Job not rendered"
# the init-users NetworkPolicy selects this label; a drift here silently isolates the pod
echo "$init" | grep -q '^        app.kubernetes.io/name: postgres-init-users$' || fail "init-users pod lost the postgres-init-users label the NetworkPolicy selects"
for db in $names; do
  # names go unquoted into SQL and, upper-cased, into an env-var name
  echo "$db" | grep -Eq '^[a-z][a-z0-9_]*$' || fail "postgres.databases name '$db' is not a plain lowercase identifier"
  up=$(echo "$db" | tr '[:lower:]' '[:upper:]')
  echo "$es" | grep -qx "t-schnappy-postgres-$db" || fail "no ExternalSecret t-schnappy-postgres-$db"
  echo "$rendered" | awk -v n="t-schnappy-postgres-$db" '/^---/ { on = 0 } $0 == "  name: " n { on = 1 } on' \
    | grep -A2 'secretKey: DB_PASSWORD$' | grep -q "key: secret/data/schnappy/postgres-$db\$" \
    || fail "ExternalSecret t-schnappy-postgres-$db does not read DB_PASSWORD from postgres-$db"
  echo "$init" | grep -A4 "^            - name: DB_PASSWORD_$up\$" | grep -q "name: t-schnappy-postgres-$db\$" \
    || fail "init-users DB_PASSWORD_$up does not read Secret t-schnappy-postgres-$db"
  echo "$init" | grep -q "CREATE ROLE $db LOGIN;" || fail "init-users has no CREATE ROLE for $db"
  echo "$init" | grep -q "ALTER ROLE $db PASSWORD :'pw';" || fail "init-users does not set $db's password from the psql variable"
  echo "$init" | grep -q "CREATE DATABASE $db OWNER $db;" || fail "init-users has no CREATE DATABASE for $db"
done
# Hand the hook script to init-users-script-test.sh (a later CI step with a real
# Postgres): the args block scalar is the 14-space-indented body after `- |`.
mkdir -p .ci-out
echo "$init" | awk '
  /^            - \|$/ { on = 1; next }
  on && /^              / { sub(/^              /, ""); print; next }
  on && /^$/ { print; next }
  on { exit }' > .ci-out/init-users.sh
[ -s .ci-out/init-users.sh ] || fail "could not extract the init-users script"
# kubelet rewrites container args before the shell sees them: `$(NAME)` becomes
# the env value and `$$` becomes `$`. Refuse the former (nothing here wants it)
# and apply the latter, so the tested script is the one the pod actually runs.
grep -Eq '\$\([A-Za-z_][A-Za-z0-9_]*\)' .ci-out/init-users.sh && fail "init-users script contains a \$(NAME) reference kubelet would expand"
sed -i 's/\$\$/$/g' .ci-out/init-users.sh
sh -n .ci-out/init-users.sh || fail "init-users script is not valid sh"
echo "$names" | tr ' ' '\n' | grep -v '^$' > .ci-out/init-users.databases

echo "chart render checks: OK"
