#!/bin/sh
# The reports server's nginx config as the chart renders it (reports on, the store at localhost:9000 - a name to resolve, as production's; the fake one
# reports-nginx-test.sh serves), out of its ConfigMap into the workspace for the next step, in the chart's nginx image
set -eu
mkdir -p .ci-out
helm template ci helm/schnappy-observability --set reports.enabled=true --set reports.minioEndpoint=localhost:9000 \
  --show-only templates/reports-configmap.yaml > /tmp/reports-cm.yaml
sed -n '/^  nginx.conf: |$/,$p' /tmp/reports-cm.yaml | tail -n +2 | sed 's/^    //' > .ci-out/reports-nginx.conf
grep -q 'listen 8080;' .ci-out/reports-nginx.conf || { echo "FAIL the reports config not rendered"; cat /tmp/reports-cm.yaml; exit 1; }
echo "PASS the reports config rendered ($(wc -l < .ci-out/reports-nginx.conf) lines)"
