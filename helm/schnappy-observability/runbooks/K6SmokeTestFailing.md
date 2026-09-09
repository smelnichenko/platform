# K6SmokeTestFailing

**Severity:** critical · **For:** none (fires on the first failing sample)

## What fired

The k6 smoke test (the Argo PostSync hook Job `<release>-k6-smoke`, run after
every sync of the app charts) reported a failed check: `k6_checks_rate` for
`$labels.check` in `$labels.namespace` is below 1 (last sample within a day).
k6 pushes the series to Mimir at the end of the run, tagged `namespace` and
`source=k6`; Prometheus evaluates the rule through its remoteRead from Mimir,
which serves only queries carrying `source="k6"`.

## Impact

A deploy's smoke test did not pass — an endpoint behind the ingress gateway,
Keycloak, or an authenticated API returned something other than expected.
Treat as a possibly-broken release until the check is explained.

## First steps

```bash
NS=<namespace>   # schnappy-production or schnappy-test
kubectl -n $NS get job ${NS}-k6-smoke
kubectl -n $NS logs job/${NS}-k6-smoke -c k6 | grep -E '✗|checks_|Token request'
```

The hook Job uses `hook-delete-policy: BeforeHookCreation` and lives 24 h, so
the failed run's log is there until the next sync. Older runs are in ClickHouse
(`logs.podlogs`, `container = 'k6'`).

| ✗ line | Look at |
|---|---|
| `health 200` / `status UP` / `actuator-readiness 200` | the monitor pods and their readiness |
| `frontend 200` | the site pods, the HTTPRoute / gateway |
| `keycloak 200` / `has issuer` | Keycloak on the Pi VIP, the public hostname |
| `token obtained` | the `k6-smoke` client in the realm, the `schnappy-k6-smoke` Secret (ESO ← Vault `schnappy/k6-smoke`) |
| `pages 200` / `feeds 200` / `inbox 200` | the monitor API with a service-account token — permissions, DB |
| `approval-mode 200` / `permissions 200` | the admin service |
| `channels 200` / `chess-games 200` | the chat / chess services |

## Verify resolved

The next sync's hook completes and the check is back at 1 (query through
Prometheus' remote read from Mimir, so keep the `source` matcher):

```promql
last_over_time(k6_checks_rate{namespace="<ns>", source="k6"}[1d])
```
