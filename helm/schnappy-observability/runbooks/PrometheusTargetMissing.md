# PrometheusTargetMissing

**Severity:** warning · **For:** 5m

## What fired

A scrape target reported `up == 0` for 5+ min. Prometheus tried to scrape `$labels.instance` for job `$labels.job` and got no answer (TCP refused, timeout, HTTP error, or auth fail).

## Impact

That target's metrics are gone for the duration. Alerts depending on those metrics may stop firing (`absent()`-based alerts will catch this; rate/increase-based won't and will go silent).

## First steps

```bash
# Why is this target down? lastError tells you
kubectl -n schnappy-infra exec prometheus-schnappy-prometheus-0 -c prometheus -- \
  wget -qO- 'http://localhost:9090/api/v1/targets?state=active' | python3 -c "
import json,sys
d=json.load(sys.stdin)
for t in d['data']['activeTargets']:
    if t['health']!='up': print(t['scrapePool'], t['labels'].get('instance'), '|', t.get('lastError','')[:200])
"
# Direct test from a pod with curl/wget
kubectl -n schnappy-infra exec deploy/schnappy-grafana -- wget -qO- http://$INSTANCE/metrics | head -5
```

## Common causes

| Symptom | Cause |
|---|---|
| `connection refused` | upstream pod not running, container crashed |
| `i/o timeout` | NetworkPolicy blocking, or upstream blocked on something |
| `403 Forbidden` | bearer token wrong/expired (e.g. Woodpecker — see WoodpeckerScrapeDown) |
| `404 Not Found` | wrong scrape path or upstream renamed `/metrics` |
| pod recently restarted | brief blip — should resolve on its own |

## Verify resolved

`up{job=$JOB,instance=$INSTANCE} == 1` for ≥ 1 minute.
