# PrometheusScrapeDurationSlow

**Severity:** warning · **For:** 15m

## What fired

A scrape job has been taking > 10s per round for 15+ min. Default scrape interval is 15-30s, so a 10s-per-target scrape leaves no room for slowness elsewhere and risks targets being marked `up=0`.

## Impact

Slow scrapes lengthen the gap between data points → alerts and dashboards lag. Eventually the scrape times out and `up{}` flips to 0, triggering `PrometheusTargetMissing`.

## First steps

```bash
# Find slowest jobs
kubectl -n schnappy-infra exec prometheus-schnappy-prometheus-0 -c prometheus -- \
  wget -qO- 'http://localhost:9090/api/v1/query?query=topk(10,scrape_duration_seconds)' | python3 -m json.tool

# Hit the offender directly to see what it's serving
kubectl -n schnappy-infra exec prometheus-schnappy-prometheus-0 -c prometheus -- \
  wget -qO- 'http://$INSTANCE/metrics' | wc -l
```

## Common causes

| Symptom | Cause |
|---|---|
| Huge metric count (>10k lines) | exporter exposing per-request labels — drop high-cardinality dims via metricRelabelings |
| Slow underlying API | exporter blocks on slow upstream (e.g. cert-manager waiting on ACME server) |
| Network latency | cross-node hop saturated — check Cilium / NodePort path |
| Slow JSON serialization | older exporter on Java — try a newer minor |

## Common fixes

- Add `metricRelabelings` to drop unused labels at scrape time.
- Bump scrape `interval` for the slow target to give it more headroom.
- Cap `sample_limit` on the ServiceMonitor to fail fast.

## Verify resolved

`scrape_duration_seconds{job=$JOB} < 5` consistently.
