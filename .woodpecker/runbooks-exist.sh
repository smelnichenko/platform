#!/bin/sh
# Every masi alert links a runbook page; the page must exist, or the link lands on the index.
# (Other app alerts are stubs by the policy in helm/schnappy-observability/runbooks/README.md;
# add an alert family here when its pages are written.)
set -eu
missing=0
for name in $(grep -hoE 'runbooks\.pmon\.dev/Masi[A-Za-z0-9]+' helm/*/templates/*.yaml | sed 's#.*/##' | sort -u); do
  if [ ! -f "helm/schnappy-observability/runbooks/$name.md" ]; then
    echo "alert $name links a runbook that does not exist: helm/schnappy-observability/runbooks/$name.md" >&2
    missing=$((missing + 1))
  fi
done
[ "$missing" -eq 0 ] || exit 1
echo "every masi alert has its runbook"
