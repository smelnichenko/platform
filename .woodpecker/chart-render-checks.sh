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

echo "chart render checks: OK"
