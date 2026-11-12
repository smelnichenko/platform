# MasiPlacesGaugeAbsent

**Severity:** warning · **For:** 30m

## What fired

masi is `up` but publishes no `masi_places`. The places alerts read it, so without it they cannot fire.

## Impact

None directly: the places are served as before. What is lost is the warning of an empty or stale country.

## First steps

```bash
kubectl -n <ns> exec deploy/<ns>-masi -c masi -- wget -qO- localhost:8080/api/masi/actuator/prometheus | grep masi_places
kubectl -n <ns> logs deploy/<ns>-masi -c masi --since=1h | grep -i 'places'
```

## Common causes

| Symptom | Cause |
|---|---|
| Absent in the pod | no places feed is registered (`PlacesConfig`): a build without one |
| Present in the pod, absent in Prometheus | the scrape: check the ServiceMonitor target |

## Fix

- Fix the scrape, or the build.

## Verification

`masi_places` has a series per country for the namespace.
