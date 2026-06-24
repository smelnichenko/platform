# KagentControllerCrashLooping

**Severity:** warning · **For:** 5m

## What fired

A `kagent-controller` pod restarted more than 3 times in 15 min (namespace `kagent`).

## Impact

Reconciliation and the kagent API flap; agents may not pick up config changes.
Advisory plane only — no impact on other workloads. If it degrades to 0 available
replicas, the critical `KagentControllerDown` fires.

## First steps

```bash
kubectl -n kagent logs deploy/kagent-controller --previous --tail=120
kubectl -n kagent get pods | grep controller
kubectl -n kagent describe pod "$(kubectl -n kagent get pod -o name | grep controller | head -1)" | sed -n '/Last State/,/Ready/p'
```

## Common causes

| Symptom in logs | Cause |
|---|---|
| `password authentication failed` / `dial tcp ...:5432` | bundled postgres down or mid-restart |
| empty `POSTGRES_DATABASE_URL` / startup panic | values DB block misconfigured |
| `AUTH_MODE` / trusted-proxy errors | controller `auth.mode` mismatch with oauth2-proxy |
| `OOMKilled` (in `describe`) | controller memory limit (512Mi) too low |

## Fix

- DB flap → steady `kagent-postgresql` first, then `kubectl -n kagent rollout restart deploy/kagent-controller`.
- OOM → raise `controller.resources.limits.memory` in `clusters/production/kagent/values.yaml`, commit, let Argo sync.
- Config error → fix values, commit; Argo self-heals.

## Verification

- Restart count stops climbing: `kubectl -n kagent get pods | grep controller`
- Alert clears once 15m pass with no new restarts
