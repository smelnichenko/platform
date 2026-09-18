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
echo "rendered $(grep -c 'alert:' "$out/rendered-rules.yaml") alert rules"
