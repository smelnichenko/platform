#!/bin/sh
# Renders the app alert rules as production sees them and runs promtool's rule syntax check
# and the unit tests under helm/schnappy/tests/rules/ against them. Two images do it: helm
# renders (step "render-rules"), then this script runs in the Prometheus image that the
# cluster runs, so a PromQL feature the rules use is one that Prometheus has.
set -eu
out=build/rules
test -f "$out/rendered-rules.yaml" || { echo "rendered rules missing: run .woodpecker/render-rules.sh first" >&2; exit 1; }
promtool check rules "$out/rendered-rules.yaml" 2>&1
for t in helm/schnappy/tests/rules/*.test.yaml; do
  cp "$t" "$out/" || { echo "cannot copy $t into $out (is the directory writable for $(id -u)?)" >&2; exit 1; }
done
cd "$out"
for t in *.test.yaml; do
  echo "== $t"
  promtool test rules "$t" 2>&1
done
