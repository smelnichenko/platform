#!/bin/sh
# Renders the app alert rules as production sees them and runs promtool's rule syntax check
# and the unit tests under helm/schnappy/tests/rules/ against them. Two images do it: helm
# renders (step "render-rules"), then this script runs in the Prometheus image that the
# cluster runs, so a PromQL feature the rules use is one that Prometheus has.
set -eu
out=build/rules
test -f "$out/rendered-rules.yaml" || { echo "rendered rules missing: run .woodpecker/render-rules.sh first" >&2; exit 1; }
promtool check rules "$out/rendered-rules.yaml"
for t in helm/schnappy/tests/rules/*.test.yaml; do
  cp "$t" "$out/"
done
cd "$out"
for t in *.test.yaml; do
  promtool test rules "$t"
done
