#!/bin/sh
# Renders Alertmanager's config as production gets it (schnappy-observability, alerts on, a test address) into a plain
# alertmanager.yml for the next step's amtool and Alertmanager itself - the ConfigMap's data key, its block unindented.
set -eu
out=build/alertmanager
mkdir -p "$out"
# the check's image is the chart's: one moved alone (Renovate follows the chart, not this pipeline) checks another version
chart_image=$(sed -n 's/^  image: \(prom\/alertmanager:.*\)$/\1/p' helm/schnappy-observability/values.yaml)
ci_image=$(awk '/- name: alertmanager-check/ { found = 1 } found && /image:/ { print $2; exit }' .woodpecker/ci.yaml)
[ -n "$chart_image" ] && [ "$chart_image" = "$ci_image" ] \
  || { echo "the check's image ($ci_image) is not the chart's ($chart_image) - move both" >&2; exit 1; }
render() {  # $1: the file, the rest: helm's extra flags
  f=$1; shift
  helm template t helm/schnappy-observability/ --namespace schnappy-infra \
    --set prometheus.enabled=true --set alertmanager.enabled=true --set alertmanager.alertEmailTo=ops@example.org \
    --set alertmanager.alertEmailFrom=alerts@example.org "$@" \
    --show-only templates/alertmanager-configmap.yaml \
    | awk 'found { sub(/^    /, ""); print } /^  alertmanager.yml: \|/ { found = 1 }' > "$out/$f"
  grep -q '^route:' "$out/$f" || { echo "no route in the rendered $f" >&2; exit 1; }
}
render alertmanager.yml
# with kagent's investigation on: its critical route (continue) must not take the cycle's notices either
render alertmanager-kagent.yml --set alertmanager.kagentInvestigate.enabled=true
# the next step runs as the Alertmanager image's user (nobody), not as root: it must be able to write here
chmod -R a+rwX "$out"
echo "rendered alertmanager.yml ($(wc -l < "$out/alertmanager.yml") lines)"
