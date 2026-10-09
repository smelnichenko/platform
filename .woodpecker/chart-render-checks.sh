#!/bin/sh
# Render checks for templates `helm lint` never sees: lint renders chart defaults, where the
# gateway routes, the LAN-only policy and its probe are all switched off.
set -eu

fail() { echo "FAIL: $*" >&2; exit 1; }
# scratch for extracted fragments (gitignored): made here, before the first check writes to it — a fresh CI clone has none
mkdir -p .ci-out

# --- schnappy-mesh: gatewayLanOnly ---------------------------------------------------------
# the gateway on means the docs policy renders, and that policy needs the allowed ranges: every environment
# with a gateway sets them, so the helper does too (the guard itself is tested below with the ranges unset)
mesh() { helm template t helm/schnappy-mesh/ --set gateway.enabled=true --set 'gatewayLanOnly.allowedCidrs={10.0.0.0/8}' "$@"; }
lan='--set gatewayLanOnly.hosts={a.example}'

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

err=$(mesh --set 'gatewayLanOnly.hosts={a.example}' --set 'gatewayLanOnly.allowedCidrs=null' 2>&1 >/dev/null) && fail "hosts without allowedCidrs rendered"
echo "$err" | grep -q 'gatewayLanOnly.allowedCidrs must list' || fail "unexpected error: $err"

# shellcheck disable=SC2086
err=$(helm template t helm/schnappy-mesh/ $lan --set 'gatewayLanOnly.allowedCidrs={10.0.0.0/8}' --show-only templates/gateway-lan-only.yaml 2>&1 >/dev/null) \
  && fail "LAN-only policy rendered with the gateway disabled"
echo "$err" | grep -q 'could not find template' || fail "unexpected error: $err"

# --- schnappy-mesh: the docs paths are LAN-only on every host ----------------------------
# shellcheck disable=SC2086
docs=$(mesh --show-only templates/gateway-docs-lan-only.yaml)
echo "$docs" | grep -q '^  action: DENY$' || fail "docs LAN-only policy is not a DENY"
for p in /api /api/masi /api/chess /api/chat /api/admin; do
  echo "$docs" | grep -q "\"$p/api-docs\*\"\$" || fail "docs policy does not cover $p/api-docs"
  echo "$docs" | grep -q "\"$p/swagger-ui\*\"\$" || fail "docs policy does not cover $p/swagger-ui"
done
echo "$docs" | grep -q 'hosts:' && fail "docs policy is bound to hosts: it must deny the paths on every host"
echo "$docs" | grep -q '"10.0.0.0/8"$' || fail "docs policy lost its allowed range"
err=$(mesh --set 'gatewayLanOnly.allowedCidrs=null' 2>&1 >/dev/null) && fail "docs prefixes without allowedCidrs rendered"
echo "$err" | grep -q 'gatewayLanOnly.allowedCidrs must list' || fail "unexpected error: $err"

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

# --- schnappy-observability: kube-state-metrics reads CloudNativePG's Cluster status (the Postgres backup alerts) ----
# Postgres' backups are CNPG's (no Job, nothing scraped its pods' 9187 - meshed): its Cluster's conditions
# (ContinuousArchiving, LastBackupSucceeded) and last successful backup, as metrics, are what the alerts read
ksmobs() { helm template t helm/schnappy-observability/ --set prometheus.enabled=true --set kubeStateMetrics.enabled=true "$@"; }
ksmdep=$(ksmobs --show-only templates/kube-state-metrics-deployment.yaml)
crsfile=$(echo "$ksmdep" | sed -n "s/.*--custom-resource-state-config-file=\([^']*\).*/\1/p")
[ -n "$crsfile" ] || fail "kube-state-metrics loads no custom resource state config"
echo "$ksmdep" | grep -q "mountPath: $(dirname "$crsfile")$" || fail "the custom resource config is not mounted at $(dirname "$crsfile")"
echo "$ksmdep" | grep -q 'checksum/custom-resources:' || fail "kube-state-metrics does not restart for a change of its custom resource config"
crs=$(ksmobs --show-only templates/kube-state-metrics-custom-resources.yaml)
echo "$crs" | grep -q 'kind: Cluster' && echo "$crs" | grep -q 'group: postgresql.cnpg.io' \
  || fail "the custom resource config does not read CNPG's Cluster"
for m in condition last_successful_backup_timestamp_seconds; do
  echo "$crs" | grep -q "name: $m$" || fail "no cnpg_cluster_$m metric"
done
ksmobs --show-only templates/kube-state-metrics-rbac.yaml | awk '/apiGroups: \["postgresql.cnpg.io"\]/ {g=1} g && /- clusters/ {print "ok"; exit}' \
  | grep -q ok || fail "kube-state-metrics may not list CNPG's Clusters"
# schnappy-data's Postgres backup alerts matched postgres-backup Jobs that do not exist: gone, the CNPG ones instead
helm template t helm/schnappy-data/ --set alerts.enabled=true --set cnpg.enabled=true --set cnpg.backup.enabled=true \
  --set postgres.password=x 2>/dev/null | grep -q 'alert: PostgresBackup' && fail "schnappy-data still alerts on postgres-backup Jobs"

# --- schnappy-observability: a failed build mails somebody only when it is main's ---------------------------------
# shellcheck disable=SC2086
helm template t helm/schnappy-observability/ $probe --show-only templates/prometheus-rules.yaml \
  | awk '/alert: WoodpeckerBuildFailed$/ {s=1; print; next} s && /- alert:/ {exit} s' | grep -v '^ *#' > .ci-out/build-failed.rule || true
grep -q 'woodpecker_step_failures_total{workflow="cd", type!="service"}' .ci-out/build-failed.rule || fail "WoodpeckerBuildFailed no longer watches the cd workflow"
grep -q 'woodpecker_pipeline_count' .ci-out/build-failed.rule && fail "WoodpeckerBuildFailed is back on woodpecker_pipeline_count, which counts every pull request as main"
grep -q 'workflow="ci", type!="service", repo=~"schnappy/(platform|infra|ops)"' .ci-out/build-failed.rule || fail "the repos that push to main directly are no longer watched"

# --- schnappy-observability: no alert reaches the LLM agents unless somebody switches that on ------------------------
am='--set prometheus.enabled=true --set alertmanager.enabled=true --set alertmanager.alertEmailTo=ops@example.org'
# shellcheck disable=SC2086
routes=$(helm template t helm/schnappy-observability/ $am --show-only templates/alertmanager-configmap.yaml | awk '/^    route:/,/^    receivers:/')
echo "$routes" | grep -q 'receiver: kagent-investigate' && fail "critical alerts are routed to kagent by default"
echo "$routes" | grep -q 'severity: critical' || fail "the human route for critical alerts is gone"
# shellcheck disable=SC2086
helm template t helm/schnappy-observability/ $am --set alertmanager.kagentInvestigate.enabled=true --show-only templates/alertmanager-configmap.yaml \
  | awk '/^    route:/,/^    receivers:/' | grep -q 'receiver: kagent-investigate' || fail "the kagent route cannot be switched on"

# --- schnappy: masi + masi-browser ----------------------------------------------------------
# masi is off by default; enabled with its browser and both secrets, the render must carry the
# controls the plan names: they are the SSRF and cost boundaries. Assertions follow a value to
# where it is consumed (secret keys, ports, parallelism) rather than grepping for words.
masi=$(helm template t helm/schnappy/ --set site.dnsResolver=10.43.0.10 --set vault.secretsEnabled=true \
  --set admin.enabled=true --set alerts.enabled=true --set smokeTest.enabled=true \
  --set masiService.enabled=true --set masiService.browser.enabled=true \
  --set masiService.browser.existingSecret=t-masi-browser \
  --set masiService.ai.enabled=true --set masiService.ai.existingSecret=t-ai-masi)
# one document by kind + name (resets at every `---`, so a same-named Service never leaks in)
doc() { echo "$masi" | awk -v k="$1" -v n="$2" '/^---/ { on = 0; k1 = 0 } $0 == "kind: " k { k1 = 1 } k1 && $0 == "  name: " n { on = 1; k1 = 0 } on'; }
# a top-level section of a doc (e.g. "  ingress:" up to the next 2-space key)
sect() { echo "$1" | awk -v h="$2" '$0 == "  " h ":" { on = 1; next } on && /^  [a-zA-Z]/ { exit } on'; }
# value of an env var in a container spec
envv() { echo "$1" | awk -v n="$2" '$0 == "            - name: " n { on = 1; next } on && /^            - name: / { exit } on && /^              value: / { sub(/^              value: /, ""); print; exit }'; }
# secret + key an env var reads from
envref() { echo "$1" | awk -v n="$2" '$0 == "            - name: " n { on = 1; next } on && /^            - name: / { exit } on && /^                  name: / { s = $2 } on && /^                  key: / { print s " " $2; exit }'; }

dep=$(doc Deployment t-schnappy-masi)
[ -n "$dep" ] || fail "masi Deployment not rendered"
[ "$(echo "$dep" | grep -c '^              path: /api/masi/actuator/health/')" = 3 ] || fail "masi startup/liveness/readiness probes do not all use the /api/masi context path"
echo "$dep" | grep -q 'prometheus.io/scrape: "true"' || fail "masi is not scraped (it would silently vanish from the alert regex)"
echo "$dep" | grep -q 'prometheus.io/path: "/api/masi/actuator/prometheus"' || fail "masi scrape path lost the context path"
for e in DB_NAME DB_USERNAME DB_PASSWORD; do [ "$(envref "$dep" $e)" = "t-schnappy-postgres-masi $e" ] || fail "masi $e does not read t-schnappy-postgres-masi/$e"; done
echo "$dep" | grep -q 'postgres-\(chess\|chat\|monitor\|admin\)' && fail "masi reads another service's postgres secret"
[ "$(envref "$dep" ANTHROPIC_API_KEY)" = "t-ai-masi ANTHROPIC_API_KEY" ] || fail "masi does not read ANTHROPIC_API_KEY from its own ai-masi secret"
echo "$dep" | grep -q 't-schnappy-ai$' && fail "masi must never read the shared ai secret"
[ "$(envref "$dep" MASI_BROWSER_TOKEN)" = "t-masi-browser TOKEN" ] || fail "masi does not read the browser token"
[ "$(envv "$dep" MASI_BROWSER_ENDPOINT)" = '"ws://t-schnappy-masi-browser:3000"' ] || fail "masi browser endpoint wrong"
[ "$(envv "$dep" PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD)" = '"1"' ] || fail "masi would try to download a browser"
[ "$(envv "$dep" SPRING_DATASOURCE_HIKARI_DATA-SOURCE-PROPERTIES)" = '"sslmode=require"' ] || fail "masi postgres connection not sslmode=require"
[ -n "$(envv "$dep" KEYCLOAK_JWKS_URI)" ] && [ -n "$(envv "$dep" KEYCLOAK_ISSUER)" ] || fail "masi lost its Keycloak JWT validation env"
echo "$dep" | grep -qi 'valkey\|redis' && fail "masi has no Valkey"
echo "$dep" | grep -q 'replicas: 1$' || fail "masi must run a single replica (in-memory scheduler)"
echo "$dep" | grep -q 'maxSurge: 0$' || fail "masi roll must not surge on the single node"
echo "$dep" | grep -q 'name: forgejo-registry$' || fail "masi lost its pull secret"
echo "$dep" | grep -q 'containerPort: 8080$' && [ "$(echo "$dep" | grep -c '^              port: 8080$')" = 3 ] || fail "masi probes/port are not all on 8080"
# the AI env block is gated on BOTH ai.enabled and the secret name
noai=$(helm template t helm/schnappy/ --set site.dnsResolver=10.43.0.10 --set masiService.enabled=true \
  --set masiService.ai.enabled=false --set masiService.ai.existingSecret=t-ai-masi --show-only templates/masi-deployment.yaml)
[ "$(envv "$noai" AI_ENABLED)" = '"false"' ] && ! echo "$noai" | grep -q ANTHROPIC_API_KEY || fail "AI env rendered with ai.enabled=false"

es=$(doc ExternalSecret t-ai-masi)
echo "$es" | grep -q 'key: secret/data/schnappy/ai-masi$' && echo "$es" | grep -q 'property: api_key$' || fail "ai-masi ExternalSecret does not read <prefix>/ai-masi api_key"
echo "$es" | grep -q 'secretKey: ANTHROPIC_API_KEY$' && echo "$es" | grep -q '^    name: t-ai-masi$' || fail "ai-masi ExternalSecret does not write t-ai-masi/ANTHROPIC_API_KEY (what masi reads)"
bes=$(doc ExternalSecret t-masi-browser)
echo "$bes" | grep -q 'key: secret/data/schnappy/masi-browser$' && echo "$bes" | grep -q 'property: token$' && echo "$bes" | grep -q 'secretKey: TOKEN$' && echo "$bes" | grep -q '^    name: t-masi-browser$' \
  || fail "masi-browser ExternalSecret does not write t-masi-browser/TOKEN from <prefix>/masi-browser token"

br=$(doc Deployment t-schnappy-masi-browser)
[ -n "$br" ] || fail "masi-browser Deployment not rendered"
echo "$br" | grep -q 'image: "ghcr.io/browserless/chromium@sha256:[0-9a-f]\{64\}"$' || fail "masi-browser image is not pinned by digest"
echo "$br" | grep -q 'automountServiceAccountToken: false$' || fail "masi-browser mounts a service-account token"
[ "$(envref "$br" TOKEN)" = "t-masi-browser TOKEN" ] || fail "masi-browser has no TOKEN (any rendered page could open a CDP session over loopback)"
[ "$(echo "$br" | grep -c 'secretKeyRef:')" = 1 ] || fail "masi-browser must reference exactly one secret key (its own token)"
echo "$br" | grep -q 'envFrom\|secretName:\|secretRef:\|csi:' && fail "masi-browser must mount no secrets"
for d in "$dep" "$br"; do
  echo "$d" | grep -q 'host\(Network\|PID\|IPC\): true' && fail "a masi pod shares a host namespace (NetworkPolicy would not apply)"
  for c in 'runAsNonRoot: true' 'readOnlyRootFilesystem: true' '- ALL' 'type: RuntimeDefault' 'allowPrivilegeEscalation: false'; do
    echo "$d" | grep -q -- "^ *$c *\(#.*\)\?\$" || fail "masi pod hardening lost '$c'"
  done
  # every volumeMount has its volume (a dangling mount is a pod that never starts)
  for v in $(echo "$d" | awk '/^            - name: / { m = $3 } /^              mountPath: / { print m }' | sort -u); do
    echo "$d" | awk '/^      volumes:/,0' | grep -q "^        - name: $v\$" || fail "volumeMount $v has no volume"
  done
done
echo "$br" | grep -q 'runAsUser: 999$' || fail "masi-browser must run as the image uid 999"
for m in /tmp /home/blessuser /dev/shm; do echo "$br" | grep -q "mountPath: $m\$" || fail "masi-browser lacks the $m emptyDir Chromium writes to"; done
shm=$(echo "$br" | awk '/^        - name: shm$/ { on = 1; next } on && /^        - name: / { exit } on')
echo "$shm" | grep -q 'medium: Memory$' && echo "$shm" | grep -q 'sizeLimit:' || fail "masi-browser /dev/shm is not a bounded memory emptyDir"
[ "$(echo "$br" | awk '/^      volumes:/,0' | grep -c 'sizeLimit:')" = 3 ] || fail "every masi-browser emptyDir must carry a sizeLimit"
echo "$br" | grep -q 'ephemeral-storage:' || fail "masi-browser limits lost ephemeral-storage"
[ "$(envv "$br" QUEUED)" = '"0"' ] || fail "masi-browser must refuse, not queue, a third session"
[ -n "$(envv "$br" TIMEOUT)" ] || fail "masi-browser has no per-session deadline"
[ "$(envv "$br" CONCURRENT)" = "$(envv "$dep" MASI_BROWSER_MAX_PARALLEL)" ] || fail "browser CONCURRENT and masi MASI_BROWSER_MAX_PARALLEL differ"
# the pod's deadline must OUTLAST masi's run deadline (by a navigation timeout plus grace), so a
# long run is ended by masi's watchdog, never by browserless mid-navigation
bt=$(envv "$br" TIMEOUT | tr -d '"'); md=$(envv "$dep" MASI_BROWSER_RUN_DEADLINE_MS | tr -d '"')
[ "$bt" -ge $((md + 60000)) ] || fail "browser TIMEOUT ($bt) does not outlast masi run deadline ($md) by 60 s"
[ "$(envv "$br" TZ)" = '"Europe/Tallinn"' ] || fail "masi-browser renders pages in the wrong time zone"
[ "$(echo "$br" | grep -c 'pressure?token=\$TOKEN')" = 3 ] || fail "masi-browser probes must hit /pressure with the token from the environment"
echo "$br" | grep -q 'path: /' && fail "masi-browser must not use httpGet probes (the token would be in the pod spec, or the probe would be refused)"
bsvc=$(doc Service t-schnappy-masi-browser)
echo "$bsvc" | grep -q 'name: http$' && echo "$bsvc" | grep -q '^    - port: 3000$' && sect "$bsvc" selector | grep -q 'app.kubernetes.io/component: masi-browser$' \
  || fail "masi-browser Service must expose 3000 as 'http' and select the browser pods"
msvc=$(doc Service t-schnappy-masi)
echo "$msvc" | grep -q 'targetPort: 8080$' && sect "$msvc" selector | grep -q 'app.kubernetes.io/component: masi$' || fail "masi Service wrong"

np=$(doc NetworkPolicy t-schnappy-masi-browser)
[ -n "$np" ] || fail "masi-browser NetworkPolicy not rendered"
echo "$np" | sed -n '/^  podSelector:/,/^  policyTypes:/p' | grep -q 'app.kubernetes.io/component: masi-browser$' || fail "masi-browser policy selects the wrong pods"
for t in Ingress Egress; do sect "$np" policyTypes | grep -qx "    - $t" || fail "masi-browser policy lost policyType $t"; done
ing=$(sect "$np" ingress)
[ "$(echo "$ing" | grep -c '^        - \(podSelector\|namespaceSelector\|ipBlock\)')" = 1 ] || fail "masi-browser ingress must have exactly one peer"
echo "$ing" | grep -q 'namespaceSelector\|ipBlock' && fail "masi-browser ingress admits a non-pod peer"
echo "$ing" | grep -q 'app.kubernetes.io/component: masi$' && echo "$ing" | grep -q 'port: 3000$' || fail "masi-browser ingress is not masi on 3000"
eg=$(sect "$np" egress)
echo "$eg" | grep -q 'k8s-app: kube-dns$' && echo "$eg" | grep -q 'port: 53$' || fail "masi-browser DNS egress is not scoped to kube-dns"
echo "$eg" | grep -q '192.168.11.5' && fail "masi-browser policy must not reach the Keycloak VIP"
echo "$eg" | grep -q '^ *port: 587$' && fail "masi-browser policy must not reach SMTP"
for c in 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 169.254.0.0/16 100.64.0.0/10; do echo "$eg" | grep -q -- "- $c\$" || fail "masi-browser egress does not exclude $c"; done
echo "$eg" | awk '/cidr: 0.0.0.0\/0/,0' | grep -q 'port: 443$' && echo "$eg" | awk '/cidr: 0.0.0.0\/0/,0' | grep -q 'port: 80$' || fail "masi-browser internet egress lost its 80/443 port list"
[ "$(echo "$eg" | grep -c 'port: ')" = 4 ] || fail "masi-browser egress has ports beyond DNS and 80/443"
cnp=$(doc CiliumNetworkPolicy t-schnappy-masi-browser-deny)
[ -n "$cnp" ] || fail "masi-browser Cilium deny policy not rendered (the namespace default-deny allows the whole cluster)"
echo "$cnp" | sed -n '/^  endpointSelector:/,/^  egressDeny:/p' | grep -q 'app.kubernetes.io/component: masi-browser$' || fail "Cilium deny policy selects the wrong endpoints"
for e in host remote-node kube-apiserver; do sect "$cnp" egressDeny | grep -qx "        - $e" || fail "Cilium deny lost egress entity $e"; done
sect "$cnp" egressDeny | grep -q 'operator: Exists' && sect "$cnp" egressDeny | grep -q 'values: \["kube-dns"\]' || fail "Cilium deny must cover every pod in every namespace except kube-dns"
sect "$cnp" egressDeny | grep -q 'key: k8s:app, operator: NotIn, values: \["istiod"\]' || fail "Cilium deny must exempt istiod or the sidecar never bootstraps (15012)"
for c in 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 169.254.0.0/16 100.64.0.0/10; do sect "$cnp" egressDeny | grep -q -- "- cidr: $c\$" || fail "Cilium deny lost CIDR $c"; done
sect "$cnp" ingressDeny | grep -q 'values: \["masi"\]' && sect "$cnp" ingressDeny | grep -qx '        - world' || fail "Cilium ingress deny must leave only masi (and a scraper) in"
sect "$cnp" ingressDeny | grep -qx '        - host' && fail "Cilium ingress deny must not include host: it blocks the kubelet probe of the sidecar (:15021)"
mnp=$(doc NetworkPolicy t-schnappy-masi-service)
[ -n "$mnp" ] || fail "masi NetworkPolicy not rendered"
for t in Ingress Egress; do sect "$mnp" policyTypes | grep -qx "    - $t" || fail "masi policy lost policyType $t"; done
meg=$(sect "$mnp" egress)
for c in 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 169.254.0.0/16 100.64.0.0/10; do echo "$meg" | grep -q -- "- $c\$" || fail "masi egress does not exclude $c"; done
for want in 'port: 5432$' 'port: 9092$' 'port: 53$' 'app.kubernetes.io/component: admin$' 'app.kubernetes.io/component: masi-browser$' 'cidr: 192.168.11.5/32$'; do
  echo "$meg" | grep -q "$want" || fail "masi egress lost '$want'"
done
echo "$meg" | grep -q '^ *port: 587$' && fail "masi policy must not reach SMTP"
echo "$meg" | grep -q 'app.kubernetes.io/component: valkey' && fail "masi policy reaches Valkey"
echo "$meg" | awk '/cidr: 0.0.0.0\/0/,/cidr: 192/' | grep -q 'port: 443$' && echo "$meg" | awk '/cidr: 0.0.0.0\/0/,/cidr: 192/' | grep -q 'port: 80$' || fail "masi internet egress lost its 80/443 port list"
sect "$mnp" ingress | grep -q 'gateway.istio.io/managed' || fail "masi ingress lost the gateway"
# --- masi's weekly digest by mail: one switch brings the sender's env, the secret and ONE extra egress port ---------
echo "$dep" | grep -q 'name: SPRING_MAIL_HOST$' && fail "masi has a mail host with its mail switched off: Boot would make a sender"
mm=$(helm template t helm/schnappy/ --set site.dnsResolver=10.43.0.10 --set vault.secretsEnabled=true --set masiService.enabled=true \
  --set masiService.mail.enabled=true --set masiService.mail.siteUrl=https://site.example --set mail.existingSecret=t-mail)
mdoc() { echo "$mm" | awk -v k="$1" -v n="$2" '/^---/ { on = 0; k1 = 0 } $0 == "kind: " k { k1 = 1 } k1 && $0 == "  name: " n { on = 1; k1 = 0 } on'; }
mdep=$(mdoc Deployment t-schnappy-masi)
for want in 'name: MASI_MAIL_ENABLED$' 'name: SPRING_MAIL_HOST$' 'value: "https://site.example"$' 'name: t-mail$' 'key: MAIL_PASSWORD$'; do
  echo "$mdep" | grep -q "$want" || fail "masi with mail on lost '$want'"
done
echo "$mdep" | grep -A1 'name: MASI_MAIL_WEEKLY_AUTO$' | grep -q 'value: "false"$' || fail "masi mails on a schedule by default: unattended mail must be opt-in"
echo "$mdep" | grep -q 'name: MASI_MAIL_DELIVER_ALL_TO$' && fail "masi has a mail sink nobody configured"
msink=$(helm template t helm/schnappy/ --set site.dnsResolver=10.43.0.10 --set masiService.enabled=true --set masiService.mail.enabled=true \
  --set masiService.mail.siteUrl=https://site.example --set masiService.mail.deliverAllTo=sink@example.org --set masiService.mail.weeklyAuto=true --set mail.existingSecret=t-mail)
echo "$msink" | grep -A1 'name: MASI_MAIL_DELIVER_ALL_TO$' | grep -q 'value: "sink@example.org"$' || fail "the configured mail sink does not reach masi"
echo "$msink" | grep -A1 'name: MASI_MAIL_WEEKLY_AUTO$' | grep -q 'value: "true"$' || fail "weeklyAuto cannot be switched on"
[ -n "$(mdoc ExternalSecret t-mail)" ] || fail "masi's mail switch alone must pull in the mail ExternalSecret (mail.enabled is off)"
mmeg=$(sect "$(mdoc NetworkPolicy t-schnappy-masi-service)" egress)
[ "$(echo "$mmeg" | grep -c '^ *port: 587$')" = 1 ] || fail "masi with mail on must reach SMTP in exactly one rule"
# the SMTP port is a rule of its own with the full except list, never a port of the fetch rule
smtp=$(echo "$mmeg" | awk '/cidr: 0.0.0.0\/0/ { blk = "" } { blk = blk "\n" $0 } /port: 587$/ { print blk; exit }')
echo "$smtp" | grep -q 'port: 443$' && fail "the SMTP port was added to masi's fetch rule"
for c in 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 169.254.0.0/16 100.64.0.0/10; do echo "$smtp" | grep -q -- "- $c\$" || fail "masi SMTP egress does not exclude $c"; done
err=$(helm template t helm/schnappy/ --set site.dnsResolver=10.43.0.10 --set masiService.enabled=true --set masiService.mail.enabled=true 2>&1 >/dev/null) \
  && fail "masi mail without a siteUrl rendered"
echo "$err" | grep -q 'masiService.mail.siteUrl is required' || fail "unexpected error: $err"

# admin admits masi in its INGRESS, and only there
adm=$(doc NetworkPolicy t-schnappy-admin)
sect "$adm" ingress | grep -q 'app.kubernetes.io/component: masi$' || fail "admin ingress does not admit masi"
sect "$adm" egress | grep -q 'app.kubernetes.io/component: masi$' && fail "admin egress must not name masi"
# alert regex: masi in, masi-browser out
rules=$(doc PrometheusRule t-schnappy-app-alerts)
echo "$rules" | grep -q 'job=~"schnappy-(monitor|admin|chat|chess|masi|game-scp|site)"' || fail "alert job regex does not include masi exactly"
echo "$rules" | grep -q 'masi-browser' && fail "alert job regex must not include masi-browser"
# k6: every skip name is a group, the masi group exists, skipped while disabled and not while enabled
smoke=helm/schnappy/files/smoke-test.js
grep -q "smoke('masi'" $smoke && grep -q "'masi'\]" $smoke || fail "smoke script lost the masi group"
k6on=$(doc Job t-schnappy-k6-smoke)
[ -n "$k6on" ] || k6on=$(echo "$masi" | awk '/^kind: Job$/ { j = 1 } j && /k6/ { on = 1 } on' )
echo "$k6on" | grep -A1 'name: K6_SKIP_GROUPS$' | grep -q 'masi' && fail "masi is skipped although enabled"
k6off=$(helm template t helm/schnappy/ --set site.dnsResolver=10.43.0.10 --set smokeTest.enabled=true --show-only templates/k6-postsync-job.yaml)
skips=$(echo "$k6off" | grep -A1 'name: K6_SKIP_GROUPS$' | tail -1 | sed 's/.*value: "//; s/"//; s/,/ /g')
echo " $skips " | grep -q ' masi ' || fail "masi is not skipped while disabled (every production PostSync would fail)"
for g in $skips; do grep -q "'$g'" $smoke || fail "K6_SKIP_GROUPS names '$g', which the smoke script does not know (k6 exits 107)"; done
# disabled: nothing masi-specific by NAME (comments may mention it)
off=$(helm template t helm/schnappy/ --set site.dnsResolver=10.43.0.10 --set vault.secretsEnabled=true --set admin.enabled=true)
echo "$off" | grep -q '^  name: t-schnappy-masi' && fail "a masi resource rendered while disabled"
echo "$off" | grep -q '^  name: .*masi-browser' && fail "a masi-browser resource rendered while disabled"
# browser enabled without its token secret must refuse to render (no open CDP server, ever)
helm template t helm/schnappy/ --set site.dnsResolver=10.43.0.10 --set masiService.enabled=true --set masiService.browser.enabled=true >/dev/null 2>&1 \
  && fail "masi-browser rendered without a token secret"
# the API docs are off unless switched on: the default renders "false", test renders "true"
echo "$masi" | grep -A1 'name: MASI_API_DOCS_ENABLED' | grep -q 'value: "false"' || fail "masi API docs must be off by default"
helm template t helm/schnappy/ --set site.dnsResolver=10.43.0.10 --set masiService.enabled=true --set masiService.apiDocs.enabled=true \
  | grep -A1 'name: MASI_API_DOCS_ENABLED' | grep -q 'value: "true"' || fail "masi API docs switch does not reach the pod"
# the browser image digest is pinned beside the masi CI sidecar; a bump must move both
helm show values helm/schnappy/ | grep -q 'digest: .sha256:b1ba7b054af2891a8199f884d4bd249cf8c3bd2fa8a97b339077e40f92803ba8' \
  || fail "browserless digest in values changed — update the masi CI sidecar pin in the same change"

# --- schnappy-mesh + schnappy-data: masi ----------------------------------------------------
mesh=$(mesh)
# every service account the app chart references exists in the mesh chart (enable masi before
# 2d and the ReplicaSet creates no pod)
for sa in $(echo "$masi" | awk '/serviceAccountName:/ { print $2 }' | sort -u); do
  echo "$mesh" | grep -q "^  name: $sa\$" || fail "service account $sa is referenced by the app chart but not created by the mesh chart"
done
ap() { echo "$mesh" | awk -v n="$1" '/^---/ { on = 0 } $0 == "  name: " n { on = 1 } on'; }
ap t-schnappy-postgres | grep -q 'sa/t-schnappy-masi$' || fail "masi principal missing from the postgres AuthorizationPolicy"
ap t-schnappy-kafka | grep -q 'sa/t-schnappy-masi$' || fail "masi principal missing from the kafka AuthorizationPolicy"
ap t-schnappy-admin-http | grep -q 'sa/t-schnappy-masi$' || fail "admin-http does not admit masi (user provisioning)"
mh=$(ap t-schnappy-masi-http)
echo "$mh" | grep -q 'schnappy-infra-gateway-istio$' || fail "masi-http does not admit the gateway"
[ "$(echo "$mh" | grep -c 'sa/t-schnappy-')" = 1 ] || fail "masi-http must admit no in-mesh service caller (only gateway, prometheus, hyperfoil)"
bh=$(ap t-schnappy-masi-browser-http)
[ -n "$bh" ] || fail "masi-browser AuthorizationPolicy not rendered"
[ "$(echo "$bh" | grep -c 'cluster.local/')" = 1 ] && echo "$bh" | grep -q 'sa/t-schnappy-masi$' && echo "$bh" | grep -q 'ports: \["3000"\]' \
  || fail "masi-browser policy must admit exactly masi's principal on 3000"
echo "$bh" | grep -q 'gateway-istio\|hyperfoil' && fail "masi-browser policy admits the gateway or hyperfoil"
echo "$mesh" | awk '/^kind: DestinationRule$/ { on = 1 } on && /^  name: / { print $2; on = 0 }' | grep -qx 't-schnappy-masi-browser' || fail "no DestinationRule for masi-browser"
echo "$mesh" | awk '/^kind: DestinationRule$/ { on = 1 } on && /^  name: / { print $2; on = 0 }' | grep -qx 't-schnappy-masi' || fail "no DestinationRule for masi"
# the route in BOTH files: longest prefix beats /api, so the failure mode is forgetting one
r1=$(echo "$mesh" | awk '/^# Source: schnappy-mesh\/templates\/httproutes.yaml/ { on = 1 } /^# Source: / && !/httproutes.yaml/ { on = 0 } on')
echo "$r1" | awk '/^  name: t-schnappy-masi-route$/ { on = 1 } on && /^---/ { exit } on' | grep -q 'value: /api/masi }' || fail "masi route missing from httproutes.yaml"
ext=$(helm template t helm/schnappy-mesh/ --set gateway.enabled=false --set gateway.external.enabled=true \
  --set gateway.external.hostname=x.example --set gateway.external.gatewayName=g --set gateway.external.gatewayNamespace=n \
  --show-only templates/httproutes-external.yaml)
echo "$ext" | awk '/^  name: t-schnappy-masi-route$/ { on = 1 } on && /^---/ { exit } on' | grep -q 'value: /api/masi }' || fail "masi route missing from httproutes-external.yaml"
echo "$ext" | awk '/^  name: t-schnappy-masi-route$/ { on = 1 } on && /^---/ { exit } on' | grep -q 'name: t-schnappy-masi$' || fail "external masi route points at the wrong backend"
ku=$(helm template t helm/schnappy-data/ --set postgres.password=test --set strimzi.enabled=true --set kafka.scram.enabled=true --show-only templates/kafka-users.yaml 2>/dev/null \
  | awk '/^  name: schnappy-masi$/ { on = 1 } on && /^---/ { exit } on')
[ -n "$ku" ] || fail "KafkaUser schnappy-masi not rendered"
echo "$ku" | grep -q 'name: "user.events"' && echo "$ku" | grep -q 'name: "masi-user"' || fail "KafkaUser schnappy-masi lost user.events or the masi-user group"
echo "$ku" | grep -q 'Write' && fail "KafkaUser schnappy-masi must not write"

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

# --- hook Jobs: each bounded on the Job (Argo waits for a hook, a rollback by revert behind it, and fails it only once
# Kubernetes fails the Job); each in-pod wait bounded by the clock; k6's deadline fits two whole tries (a cold one
# retried), derived from its wait and k6's own maxDuration
job_deadline() { awk '/^spec:/ {s=1; next} /^[^ ]/ {s=0} s && /^  activeDeadlineSeconds:/ {print $2}'; }
k6=$(helm template t helm/schnappy/ --set site.dnsResolver=10.43.0.10 --set smokeTest.enabled=true --show-only templates/k6-postsync-job.yaml)
schema=$(helm template t helm/schnappy-data/ --show-only templates/scylla-schema-job.yaml)
gwjob=$(mesh $lan --show-only templates/gateway.yaml | awk '/^kind: Job$/ {j=1} /^---/ {j=0} j')
chinit=$(helm template t helm/schnappy-observability/ --set clickhouse.enabled=true \
  --show-only templates/clickhouse-init-job.yaml | awk '/^kind: Job$/ {j=1} /^---/ {j=0} j')
# five databases, production's count: the deadline grows with them
users=$(helm template t helm/schnappy-data/ --set cnpg.enabled=true --set 'postgres.databases[0].name=a' \
  --set 'postgres.databases[1].name=b' --set 'postgres.databases[2].name=c' --set 'postgres.databases[3].name=d' \
  --set 'postgres.databases[4].name=e' \
  --show-only templates/cnpg-init-users.yaml)
sqsetup=$(helm template t helm/schnappy-sonarqube/ --set sonarqube.enabled=true --set sonarqube.setup.enabled=true \
  --set sonarqube.postgres.password=x --set 'sonarqube.setup.projects[0].key=p1' --set 'sonarqube.setup.projects[0].name=P one' \
  --set 'sonarqube.setup.projects[0].gate=Service' \
  $(for i in 1 2 3 4 5 6 7 8; do printf -- "--set sonarqube.setup.projects[%s].key=p%s --set sonarqube.setup.projects[%s].name=p%s " $i $((i + 1)) $i $((i + 1)); done) \
  --show-only templates/sonarqube-setup-job.yaml)
# production's count (infra's schnappy-sonarqube values: 9): its deadline grows with them
[ "$(echo "$sqsetup" | grep -c 'api/projects/search?q=')" = 9 ] || fail "the sonarqube setup not rendered with production's 9 projects"
# the setup script as the pod runs it, for .woodpecker/sonarqube-setup-script-test.sh
echo "$sqsetup" | awk '/^            - \|$/ {s=1; next} s && /^          [a-z]/ {exit} s {sub(/^              /, ""); print}' \
  > .ci-out/sonarqube-setup.sh
grep -q '^set -eu$' .ci-out/sonarqube-setup.sh || fail "the sonarqube setup script not extracted"
pcleanup=$(helm template t helm/schnappy/ --set site.dnsResolver=10.43.0.10 --set previewMode=true --set previewNumber=7 \
  --show-only templates/preview-cleanup-job.yaml | awk '/^kind: Job$/ {j=1} /^---/ {j=0} j')
# the scripts as their pods run them, for .woodpecker/hook-scripts-test.sh: the first "- |" block of each Job
first_script() { awk '/^ *- \|$/ {s=1; match($0, /^ */); ind=RLENGTH + 2; next} s && /^ *[a-zA-Z][a-zA-Z_]*:/ && match($0, /^ */) && RLENGTH < ind {exit} s {print substr($0, ind + 1)}'; }
echo "$schema" | first_script > .ci-out/scylla-schema.sh
echo "$gwjob" | first_script > .ci-out/gateway-patch.sh
echo "$pcleanup" | awk '/^kind: Job$/ {j=1} /^---/ {j=0} j' | first_script > .ci-out/preview-cleanup.sh
for s in scylla-schema gateway-patch preview-cleanup; do
  grep -q '^set -eu$' ".ci-out/$s.sh" || fail "the $s hook script not extracted"
done
s3jobs=$(helm template t helm/schnappy-data/ --set s3gw.enabled=true --set s3gw.existingSecret=s --set s3gw.storage.size=1Gi \
  --set 's3gw.buckets={a}' --show-only templates/s3gw-buckets-job.yaml)
# the hook Job templates judged below, by chart and file: every one the scan of the charts finds must be among them
judged="schnappy/templates/k6-postsync-job.yaml schnappy-data/templates/scylla-schema-job.yaml
schnappy-mesh/templates/gateway.yaml schnappy-observability/templates/clickhouse-init-job.yaml
schnappy-data/templates/cnpg-init-users.yaml schnappy-sonarqube/templates/sonarqube-setup-job.yaml
schnappy/templates/preview-cleanup-job.yaml schnappy-data/templates/s3gw-buckets-job.yaml"
# every loop that sleeps - nested, one-line, its "do" on the next line - reads the clock inside it (a read in a loop
# nested in it counts: it runs each round), the bound set before it on a line of its own (not a comment). A loop is a
# for/while/until starting a statement
clock_bound() { awk '/^ *#/ {next} /^ *(start=[^;]*; )?end=\$\(\( \$\(date \+%s\) \+ [0-9]+ \)\)$/ {e=1}
  { opens = gsub(/(^ *|[;&|(] *)(for|while|until) /, "&"); closes = gsub(/(^|[ ;])done($|[ ;)])/, "&") }
  { for (k = 0; k < opens; k++) {d++; slp[d] = 0; clk[d] = 0} }
  d && /-lt "\$end"/ {for (k = 1; k <= d; k++) clk[k] = 1}
  d && /(^|[ ;])sleep / {slp[d] = 1}
  { for (k = 0; k < closes && d > 0; k++) {if (slp[d] && !(e && clk[d])) bad = 1; d--} }
  END {exit bad}'; }
# each "- |" script block's first command (blank and comment lines aside) is set -e
set_e_first() { awk '/^ *- \|$/ {s=1; next} s && /^ *(#|$)/ {next} s {if ($0 !~ /^ *set -e/) bad=1; s=0} END {exit bad}'; }
# a hook's deadline holds its waits (the end= seconds, one after another: summed), 120 s, and each call at its own bound
wait_bound() { sed -n 's/.*end=\$(( \$(date +%s) + \([0-9][0-9]*\) )).*/\1/p' | awk '{t += $1} END {if (NR) print t}'; }
# each client call costed by its own time-out, read from the call (continued lines joined): curl --max-time, wget -T,
# cqlsh --connect-timeout + --request-timeout, kubectl the `timeout N` before it, clickhouse-client --connect_timeout +
# --receive_timeout, aws 40 s to start + its connect and read; sq (curl --max-time 10 itself) 10, psql the pod's
# connect and statement time-outs (the first argument). A call without its time-out: "UNBOUNDED <the line>". kubectl in
# a pod is never bounded by its own --request-timeout: any client flag of that kind (--request-timeout, --server,
# --token, ...) makes it drop the in-cluster config and dial localhost:8080 - "OVERRIDE <the line>"
calls_cost() { sed -e ':a' -e '/\\$/N; s/\\\n//; ta' | awk -v psql="$1" '/^ *#/ {next}
  { line = $0
    n = gsub(/(^|[ ;(|&$`'"'"'"])curl /, "&", line)
    for (k = 0; k < n; k++) { if (match(line, /--max-time [0-9]+/)) { split(substr(line, RSTART, RLENGTH), a, " "); t += a[2] } else { print "UNBOUNDED " $0; u = 1; exit } }
    n = gsub(/(^|[ ;(|&$`'"'"'"])wget /, "&", line)
    for (k = 0; k < n; k++) { if (match(line, /-T [0-9]+/)) { split(substr(line, RSTART, RLENGTH), a, " "); t += a[2] } else { print "UNBOUNDED " $0; u = 1; exit } }
    n = gsub(/(^|[ ;(|&$])cqlsh /, "&", line)
    for (k = 0; k < n; k++) { if (match(line, /--connect-timeout=[0-9]+/) && (c = substr(line, RSTART + 18, RLENGTH - 18)) && match(line, /--request-timeout=[0-9]+/)) t += c + substr(line, RSTART + 18, RLENGTH - 18); else { print "UNBOUNDED " $0; u = 1; exit } }
    if (match(line, /(^|[ ;(|&$])kubectl [^;|&]*--(request-timeout|server|token|certificate-authority|insecure-skip-tls-verify|user|cluster|context)[= ]/)) { print "OVERRIDE " $0; u = 1; exit }
    n = gsub(/(^|[ ;(|&$])kubectl /, "&", line); rest = line
    for (k = 0; k < n; k++) { if (match(rest, /(^|[ ;(|&$])timeout [0-9]+ kubectl /)) { split(substr(rest, RSTART, RLENGTH), a, "timeout "); t += a[2] + 0; rest = substr(rest, RSTART + RLENGTH) } else { print "UNBOUNDED " $0; u = 1; exit } }
    n = gsub(/(^|[ ;(|&$])clickhouse-client /, "&", line)
    for (k = 0; k < n; k++) { if (match(line, /--connect_timeout [0-9]+/) && (c = substr(line, RSTART + 18, RLENGTH - 18)) && match(line, /--receive_timeout [0-9]+/)) t += c + substr(line, RSTART + 18, RLENGTH - 18); else { print "UNBOUNDED " $0; u = 1; exit } }
    n = gsub(/(^|[ ;(|&$])aws /, "&", line)
    for (k = 0; k < n; k++) { if (match(line, /--cli-connect-timeout [0-9]+/) && (c = substr(line, RSTART + 22, RLENGTH - 22)) && match(line, /--cli-read-timeout [0-9]+/)) t += 40 + c + substr(line, RSTART + 19, RLENGTH - 19); else { print "UNBOUNDED " $0; u = 1; exit } }
    n = gsub(/(^|[ ;(|&$])sq /, "&", line); t += 10 * n
    n = gsub(/(^|[ ;(|&$])psql /, "&", line); if (n && psql == "") { print "UNBOUNDED " $0; u = 1; exit } t += psql * n }
  END { if (!u) print t + 0 }'; }
# the waits summed: two waits of 100 s and 200 s, one after another, are 300 s
[ "$(printf '%s\n' '  end=$(( $(date +%s) + 100 ))' '  end=$(( $(date +%s) + 200 ))' | wait_bound)" = 300 ] \
  || fail "the waits are not summed"
# clock_bound against hand-built loops: a sleeping loop needs end= before it and a -lt "$end" read in it or a loop inside
cb() { if printf '%s\n' "$@" | clock_bound; then echo pass; else echo fail; fi; }
E='end=$(( $(date +%s) + 30 ))'; R='[ "$(date +%s)" -lt "$end" ] || exit 1'
[ "$(cb "$E" 'for i in $(seq 1 9); do' "  $R" '  sleep 1' 'done')" = pass ] || fail "clock_bound: a bounded loop refused"
[ "$(cb "$E" 'for i in $(seq 1 9); do' '  sleep 1' 'done')" = fail ] || fail "clock_bound: a sleeping loop with no clock read passed"
[ "$(cb "$E" 'for i in $(seq 1 9)' 'do' '  sleep 1' 'done')" = fail ] || fail "clock_bound: do on the next line, no clock, passed"
[ "$(cb 'for i in $(seq 1 9); do' "  $R" '  sleep 1' 'done')" = fail ] || fail "clock_bound: no end= before the loop passed"
[ "$(cb "$E" 'for i in $(seq 1 9); do' "  $R" '  for j in 1 2; do sleep 1; done' 'done')" = fail ] \
  || fail "clock_bound: an inner loop sleeping with the clock only in the outer passed"
[ "$(cb "$E" 'for i in $(seq 1 9); do' "  for j in 1 2; do $R; done" '  sleep 1' 'done')" = pass ] \
  || fail "clock_bound: the clock read in an inner loop refused"
[ "$(cb "$E" "for i in \$(seq 1 9); do $R; sleep 1; done")" = pass ] || fail "clock_bound: a one-line bounded loop refused"
[ "$(cb "$E" 'for i in $(seq 1 9); do sleep 1; done')" = fail ] || fail "clock_bound: a one-line unbounded loop passed"
[ "$(cb "$E" 'for i in $(seq 1 9); do' "  $R" 'done' 'for k in $(seq 1 9); do' '  sleep 1' 'done')" = fail ] \
  || fail "clock_bound: a second loop sleeping without a clock passed"
[ "$(cb "$E" 'x=$(for i in 1 2; do sleep 1; done)')" = fail ] || fail "clock_bound: a loop in a substitution passed"
# each client's call: costed by its own time-out, refused without it
cc() { printf '%s\n' "$1" | calls_cost "${2:-}"; }
[ "$(cc 'curl -fsS --max-time 7 http://x')" = 7 ] && [ "$(cc 'curl -fsS http://x')" = "UNBOUNDED curl -fsS http://x" ] \
  || fail "calls_cost: curl's --max-time not read"
[ "$(cc 'wget -T 9 -qO- http://x')" = 9 ] && [ "$(cc 'wget -qO- http://x')" = "UNBOUNDED wget -qO- http://x" ] \
  || fail "calls_cost: wget's -T not read"
[ "$(cc 'cqlsh --connect-timeout=5 --request-timeout=60 h 9042')" = 65 ] \
  && [ "$(cc 'cqlsh --connect-timeout=5 h 9042')" = "UNBOUNDED cqlsh --connect-timeout=5 h 9042" ] || fail "calls_cost: cqlsh's time-outs not read"
[ "$(cc 'clickhouse-client --connect_timeout 5 --receive_timeout 300 -q x')" = 305 ] \
  && [ "$(cc 'clickhouse-client --connect_timeout 5 -q x')" = "UNBOUNDED clickhouse-client --connect_timeout 5 -q x" ] \
  || fail "calls_cost: clickhouse-client's time-outs not read"
[ "$(cc 'aws --cli-connect-timeout 5 --cli-read-timeout 15 s3 ls')" = 60 ] \
  && [ "$(cc 'aws s3 ls')" = "UNBOUNDED aws s3 ls" ] || fail "calls_cost: aws's time-outs not read"
[ "$(cc 'psql -c x' 65)" = 65 ] && [ "$(cc 'psql -c x')" = "UNBOUNDED psql -c x" ] || fail "calls_cost: psql's bound not taken"
# kubectl: costed by the timeout before each call (10 + 60); its own --request-timeout refused, never costed
[ "$(printf '%s\n' '  timeout 10 kubectl get svc a && break' '  kubectl get x | xargs -r timeout 60 kubectl delete' \
  | calls_cost '')" = "UNBOUNDED   kubectl get x | xargs -r timeout 60 kubectl delete" ] \
  || fail "a kubectl call without its timeout is not refused"
[ "$(printf '%s\n' '  timeout 10 kubectl get svc a && break' '  timeout 10 kubectl get x | xargs -r timeout 60 kubectl delete' \
  | calls_cost '')" = 80 ] || fail "kubectl calls are not costed by their timeouts"
case $(echo '  timeout 10 kubectl --request-timeout=10s get svc a' | calls_cost '') in OVERRIDE*) ;;
  *) fail "a kubectl --request-timeout in a pod is not refused" ;; esac
for pair in "k6:$k6" "schema:$schema" "gateway:$gwjob" "clickhouse-init:$chinit" "init-users:$users" \
  "sonarqube-setup:$sqsetup" "preview-cleanup:$pcleanup" "s3gw-buckets:$s3jobs"; do
  name=${pair%%:*}; body=${pair#*:}
  [ -n "$(echo "$body" | job_deadline)" ] || fail "the $name hook Job has no activeDeadlineSeconds on its spec"
  echo "$body" | grep -q '^      activeDeadlineSeconds:' && fail "the $name hook Job's deadline on its pod spec bounds one try, not the Job"
  echo "$body" | grep -qE '^ *(until|while) ' && fail "the $name hook Job waits in a loop without a clock bound (until/while)"
  echo "$body" | clock_bound || fail "the $name hook Job's wait reads no clock in its loop (end=\$(( \$(date +%s) + N )) before it, -lt \"\$end\" in it)"
  # every script of it stops at its first failing command: without set -e a failed or timed-out call ran on to "done" and
  # the hook reported success (the gateway's patch, the Scylla schema)
  echo "$body" | set_e_first || fail "the $name hook Job has a script not starting with set -e"
  w=$(echo "$body" | wait_bound)
  # psql's bound: the pod's PGCONNECT_TIMEOUT and statement_timeout (PGOPTIONS), when the Job sets them
  pc=$(echo "$body" | grep -A1 'name: PGCONNECT_TIMEOUT' | sed -n 's/.*value: "\([0-9]*\)".*/\1/p')
  ps=$(echo "$body" | sed -n 's/.*statement_timeout=\([0-9]*\)s.*/\1/p' | head -1)
  cost=$(echo "$body" | calls_cost "$([ -n "$pc" ] && [ -n "$ps" ] && echo $((pc + ps)))")
  case $cost in
    UNBOUNDED*) fail "the $name hook Job has a call without its time-out: ${cost#UNBOUNDED }" ;;
    OVERRIDE*) fail "the $name hook Job's kubectl drops its in-cluster config (bound it with timeout N): ${cost#OVERRIDE }" ;;
  esac
  [ "$(echo "$body" | job_deadline)" -ge $((${w:-0} + 120 + cost)) ] \
    || fail "the $name hook Job's deadline $(echo "$body" | job_deadline) s cannot hold its ${w:-0} s of waits, 120 s and its calls' $cost s"
  ttl=$(echo "$body" | awk '/^spec:/ {s=1; next} /^[^ ]/ {s=0} s && /^  ttlSecondsAfterFinished:/ {print $2}')
  [ -z "$ttl" ] || [ "$ttl" -ge 86400 ] \
    || fail "the $name hook Job deletes itself $ttl s after it ends: a failed one keeps its pod and log until the next sync"
done
hooks=""
for f in helm/*/templates/*.yaml; do
  awk '/^---/ {if (job && hook) print FILENAME; job=hook=0; next} /^kind: Job *$/ {job=1}
    /^    "?(argocd\.argoproj\.io|helm\.sh)\/hook"?:/ {hook=1} END {if (job && hook) print FILENAME}' "$f" | grep -q . \
    && hooks="$hooks ${f#helm/}"
  awk -v f="$f" '/^---/ {if (job && hook && !dl) {print f; bad=1} job=hook=dl=0; next}
    /^kind: Job *$/ {job=1} /^    "?(argocd\.argoproj\.io|helm\.sh)\/hook"?:/ {hook=1} /^  activeDeadlineSeconds:/ {dl=1}
    END {if (job && hook && !dl) {print f; bad=1}; exit bad}' "$f" || fail "$f: a hook Job without activeDeadlineSeconds on its spec"
done
echo "$users" | grep -A1 'name: PGCONNECT_TIMEOUT' | grep -q 'value: "5"' \
  || fail "init-users' psql calls are not bounded (PGCONNECT_TIMEOUT)"
echo "$users" | grep -A1 'name: PGOPTIONS' | grep -q 'statement_timeout=[0-9]*s.*lock_timeout=[0-9]*s' \
  || fail "init-users' statements are not bounded (PGOPTIONS statement_timeout and lock_timeout)"
# the options as the pod gets them, for .woodpecker/init-users-script-test.sh
echo "$users" | grep -A1 'name: PGOPTIONS' | sed -n 's/.*value: "\(.*\)".*/\1/p' > .ci-out/init-users.pgoptions
[ "$(echo "$chinit" | grep -c -- '--connect_timeout 5 --receive_timeout 10')" -ge 1 ] \
  || fail "clickhouse-init's wait call is not bounded (--connect_timeout, --receive_timeout)"
# every Job of schnappy-data is a hook: the data apps compare no Job (infra's data-envs ignores none of their fields)
for f in helm/schnappy-data/templates/*.yaml; do
  awk '/^---/ {if (job && !hook) bad=1; job=hook=0; next} /^kind: Job *$/ {job=1}
    /^    "?(argocd\.argoproj\.io|helm\.sh)\/hook"?:/ {hook=1} END {if (job && !hook) bad=1; exit bad}' "$f" \
    || fail "$f: a schnappy-data Job that is no hook (the data apps would compare it, its labels and selector set by Kubernetes)"
done
for h in $hooks; do
  case " $(echo $judged) " in *" $h "*) ;; *) fail "hook Job template $h is not among the judged ones (add its render)";; esac
done
wait_s=$(echo "$k6" | sed -n 's/.*end=\$(( \$(date +%s) + \([0-9][0-9]*\) )).*/\1/p' | head -1)
k6_max=$(sed -n "s/.*maxDuration: '\([0-9][0-9]*\)m'.*/\1/p" helm/schnappy/files/smoke-test.js | head -1)
[ -n "$k6_max" ] || fail "smoke-test.js gives k6 no maxDuration (k6's default 10 m makes a try outlast any deadline)"
# per try: the wait (its last sleep and curl past the clock), k6, 30 s, the pod's start (60 s); the backoff 10 s
sleep_s=$(echo "$k6" | sed -n 's/^ *sleep \([0-9][0-9]*\)$/\1/p' | head -1)
curl_s=$(echo "$k6" | sed -n 's/.*curl .*--max-time \([0-9][0-9]*\).*/\1/p' | head -1)
[ -n "$sleep_s" ] && [ -n "$curl_s" ] || fail "the k6 hook's wait: its sleep or its curl --max-time not found"
need=$(( 2 * (wait_s + sleep_s + curl_s + k6_max * 60 + 30 + 60) + 10 ))
[ "$(echo "$k6" | job_deadline)" -ge "$need" ] || fail "the k6 hook's deadline $(echo "$k6" | job_deadline) s cannot hold two tries ($need s)"

# --- the s3gw bucket hook Job: its deadline holds two passes of every aws call at its worst and the pod's start ----
# aws-cli v2 starts in seconds on a free CPU, in ~37 s on a loaded node (the upgrade copy's build, 2026-10-11: 120 s
# for three buckets, a policy and a listing ran out, Argo's sync failed)
buckets_job=$(helm template t helm/schnappy-data/ --set s3gw.enabled=true --set s3gw.existingSecret=s --set s3gw.storage.size=1Gi \
  --set 's3gw.buckets={a,b,c}' --set 's3gw.publicReadBuckets={c}' --show-only templates/s3gw-buckets-job.yaml)
[ "$(echo "$buckets_job" | sed -n 's/.*requests: { cpu: \([0-9]*\)m.*/\1/p')" -ge 500 ] \
  || fail "the bucket Job requests under 500m CPU (a loaded node shares CPU by request: aws-cli starved at 25m)"
# each call bounded: aws-cli's own defaults are 60 s connect and read, three attempts
[ "$(echo "$buckets_job" | grep -c -- '--cli-connect-timeout 5 --cli-read-timeout 15 ')" -eq 2 ] \
  && echo "$buckets_job" | grep -A1 'name: AWS_MAX_ATTEMPTS' | grep -q 'value: "2"' \
  || fail "the bucket Job's aws calls are not each bounded (timeouts on s3() and the listing, AWS_MAX_ATTEMPTS 2)"
calls=$(echo "$buckets_job" | grep -oE '(^ *|[|&;] *)(s3|aws) ' | wc -l)
connect=$(echo "$buckets_job" | sed -n 's/.*--cli-connect-timeout \([0-9]*\) .*/\1/p' | head -1)
read_s=$(echo "$buckets_job" | sed -n 's/.*--cli-read-timeout \([0-9]*\) .*/\1/p' | head -1)
attempts=$(echo "$buckets_job" | grep -A1 'name: AWS_MAX_ATTEMPTS' | sed -n 's/.*value: "\([0-9]*\)".*/\1/p')
[ -n "$connect" ] && [ -n "$read_s" ] && [ -n "$attempts" ] || fail "the bucket Job's call bounds not found"
# two passes of every call at its worst (40 s to start aws-cli on a loaded node, its attempts of connect and read) and
# 120 s for the pod's start
need=$(( 120 + 2 * calls * (40 + attempts * (connect + read_s)) ))
have=$(echo "$buckets_job" | job_deadline)
[ "$calls" -ge 8 ] || fail "the bucket Job's aws calls not found ($calls of 3 heads, 3 creates, a policy, a listing)"
[ "${have:-0}" -ge "$need" ] || fail "the s3gw bucket Job's deadline ${have:-none} s cannot hold two passes of $calls aws calls at their worst and the pod's start ($need s)"

# --- every Job's pods are out of Velero's backups -------------------------------------------------------------------
# a Job's pod that ends while a backup reads its volumes fails that volume and the whole backup is PartiallyFailed
# (the weekly backup, every week until 2026-10-11: hyperfoil-load at 03:00 and the hourly etcd-backup); the pods
# hold nothing to restore, the Job objects stay in the backup. Each Job and CronJob kind in a template carries the
# label on its pod template, where Velero reads it (read by indentation; the hyperfoil CronJob's render read too)
# the Job/CronJob kinds in a file and the pod templates of those carrying the label: "<kinds> <labelled>"
label_counts() { awk '/^---/ {injob = 0; st = 0; next} /^ *$/ {next} {ind = match($0, /[^ ]/) - 1}
    /^ *kind: / {injob = 0} /^ *kind: (Job|CronJob) *$/ {jobs++; injob = 1}
    st && ind <= t {st = 0} st == 2 && ind <= t + 2 {st = 0} st == 3 && ind <= t + 4 {st = 0}
    /^ *template: *$/ {t = ind; st = 1; next}
    st == 1 && ind == t + 2 && /metadata: *$/ {st = 2; next}
    st == 2 && ind == t + 4 && /labels: *$/ {st = 3; next}
    st == 3 && ind == t + 6 && injob && /velero\.io\/exclude-from-backup: "true"/ {marks++; st = 0}
    END {print jobs + 0, marks + 0}' "$1"; }
# its guard on the kind: a labelled Deployment beside an unlabelled Job counts nothing for the Job
printf '%s\n' 'kind: Deployment' 'spec:' '  template:' '    metadata:' '      labels:' \
  '        velero.io/exclude-from-backup: "true"' '---' 'kind: Job' 'spec:' '  template:' '    metadata:' \
  '      labels:' '        app: x' > .ci-out/label-fixture.yaml
[ "$(label_counts .ci-out/label-fixture.yaml)" = "1 0" ] || fail "the label count credits a non-Job's pod template to a Job"
for f in helm/*/templates/*.yaml; do
  got=$(label_counts "$f")
  [ "${got% *}" -le "${got#* }" ] || fail "$f: ${got% *} Job/CronJob kind(s), ${got#* } pod template(s) with velero.io/exclude-from-backup"
  seen=$(( ${seen:-0} + ${got% *} ))
done
[ "${seen:-0}" -ge 10 ] || fail "the label check saw ${seen:-0} Job/CronJob kinds in the charts (11 there): the scan reads nothing"
hf=$(helm template t helm/schnappy/ --set site.dnsResolver=10.43.0.10 --set hyperfoil.enabled=true \
  --show-only templates/hyperfoil-load-cronjob.yaml)
echo "$hf" | awk '/^      template:/{t=1} t && /^          labels:/{l=1; next} l && !/^            /{exit} l' \
  | grep -q 'velero.io/exclude-from-backup: "true"' \
  || fail "the hyperfoil-load CronJob's pod template lacks velero.io/exclude-from-backup (it runs into the weekly backup)"

echo "chart render checks: OK"
