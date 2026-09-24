#!/bin/sh
# Renders the PrometheusRule as production sees it (alerts on, masi on) into a plain rules file
# (`groups:` at the top level) for promtool. The CR's spec is the rules document, two levels in.
set -eu
out=build/rules
mkdir -p "$out"
helm template t helm/schnappy/ --namespace schnappy-production --set site.dnsResolver=10.43.0.10 \
  --set alerts.enabled=true --set masiService.enabled=true \
  --show-only templates/prometheus-rules.yaml \
  | awk 'found { sub(/^  /, ""); print } /^spec:/ { found = 1 }' > "$out/rendered-rules.yaml"
grep -q '^groups:' "$out/rendered-rules.yaml" || { echo "rendered rules have no groups" >&2; exit 1; }
grep -q 'alert: MasiBudgetDay' "$out/rendered-rules.yaml" || { echo "masi group not rendered" >&2; exit 1; }
# the cluster-wide rules (schnappy-observability), as the infra namespace renders them
helm template t helm/schnappy-observability/ --namespace schnappy-infra \
  --set prometheus.enabled=true --set alertmanager.enabled=true \
  --show-only templates/prometheus-rules.yaml \
  | awk 'found { sub(/^  /, ""); print } /^spec:/ { found = 1 }' > "$out/rendered-infra-rules.yaml"
grep -q 'alert: KubeJobFailed' "$out/rendered-infra-rules.yaml" || { echo "infra rules not rendered" >&2; exit 1; }
# the next step runs as the Prometheus image's user (nobody), not as root: it must be able to write here
chmod -R a+rwX "$out"
echo "rendered $(grep -c 'alert:' "$out/rendered-rules.yaml") app and $(grep -c 'alert:' "$out/rendered-infra-rules.yaml") infra alert rules"
