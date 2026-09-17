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
[ "$(envv "$br" TIMEOUT)" = "$(envv "$dep" MASI_BROWSER_RUN_DEADLINE_MS)" ] || fail "browser TIMEOUT and masi run deadline differ"
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
# the browser image digest is pinned beside the masi CI sidecar; a bump must move both
helm show values helm/schnappy/ | grep -q 'digest: .sha256:b1ba7b054af2891a8199f884d4bd249cf8c3bd2fa8a97b339077e40f92803ba8' \
  || fail "browserless digest in values changed — update the masi CI sidecar pin in the same change"

# --- schnappy-mesh + schnappy-data: masi ----------------------------------------------------
mesh=$(helm template t helm/schnappy-mesh/ --set gateway.enabled=true)
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
