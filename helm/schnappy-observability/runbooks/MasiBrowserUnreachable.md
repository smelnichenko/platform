# MasiBrowserUnreachable

**Severity:** warning · **For:** 10m

## What fired

`masi_browser_reachable == 0`: masi's periodic connect to the `masi-browser` pod fails.

## Impact

Browser sources end `SKIPPED_BROWSER` (that does not count as a failure and never disables them). Deterministic sources are unaffected.

## First steps

`<ns>` is `schnappy-production` or `schnappy-test`; the deployment is `<ns>-masi` (browser: `<ns>-masi-browser`).

```bash
kubectl -n <ns> get pods -l app.kubernetes.io/component=masi-browser
kubectl -n <ns> logs deploy/<ns>-masi-browser -c masi-browser --tail=50
kubectl -n <ns> logs deploy/<ns>-masi -c masi --since=30m | grep -i browser
```

## Common causes

| Symptom | Cause |
|---|---|
| Pod OOMKilled / restarting | a heavy page; the limit is 2Gi and `/dev/shm` 512Mi |
| Pod NotReady forever | sidecar cannot reach istiod, or its readiness probe is denied: see the `masi-browser-deny` policy comments |
| 401 on connect | `MASI_BROWSER_TOKEN` and the browser's `TOKEN` differ (ExternalSecret `masi-browser`) |
| Connection refused from masi | the Istio ALLOW policy or the NetworkPolicy no longer matches masi's labels |

## Fix

- Restart the browser deployment for a wedged Chromium; fix policy or secret drift in the chart, not by hand.

## Verification

Gauge back to 1; the next browser run is `OK`.
