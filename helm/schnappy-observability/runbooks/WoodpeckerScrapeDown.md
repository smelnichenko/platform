# WoodpeckerScrapeDown

**Severity:** warning · **For:** 10m

## What fired

Prometheus can't scrape `job=woodpecker-server-metrics` for 10+ min. `up{job="woodpecker-server-metrics"} == 0`.

## Impact

**Build-failure alerts go silent.** `WoodpeckerBuildFailed` is built on `woodpecker_pipeline_count` — without scrapes, the counter doesn't update, no alert fires for actually-broken builds.

## First steps

```bash
kubectl -n woodpecker get pod woodpecker-server-0
kubectl -n woodpecker get svc woodpecker-server-metrics -o jsonpath='{.spec.ports}{"\n"}'
kubectl -n woodpecker get endpoints woodpecker-server-metrics

# Hit the metrics endpoint with the bearer token from the secret
TOKEN=$(kubectl -n woodpecker get secret woodpecker-ci-secrets \
  -o jsonpath='{.data.WOODPECKER_PROMETHEUS_AUTH_TOKEN}' | base64 -d)
kubectl -n woodpecker exec woodpecker-server-0 -- \
  curl -sf -H "Authorization: Bearer $TOKEN" http://localhost:9001/metrics | head -5
```

## Common causes

| Symptom | Cause |
|---|---|
| `connection refused :9001` | Woodpecker server isn't listening on 9001 — check `WOODPECKER_METRICS_SERVER_ADDR` env var |
| `403 Forbidden` | bearer token in `woodpecker-ci-secrets.WOODPECKER_PROMETHEUS_AUTH_TOKEN` doesn't match what the server expects (chart sourced via `extraSecretNamesForEnvFrom`) |
| Service has no endpoints | label selector mismatch on woodpecker-server-metrics Service — should be `app.kubernetes.io/name=server, instance=woodpecker` |
| Empty token in k8s secret | ESO sync failing — see ExternalSecretSyncFailing |

## Resync the token if needed

```bash
cd /home/sm/src/ops && task deploy:seed-secrets
kubectl -n woodpecker annotate externalsecret woodpecker-ci-secrets-es force-sync=$(date +%s) --overwrite
kubectl -n woodpecker rollout restart statefulset woodpecker-server  # so the new env var is picked up
```

## Verify resolved

`up{job="woodpecker-server-metrics"} == 1`.
