# KagentControllerDown

**Severity:** critical · **For:** 10m

## What fired

The `kagent-controller` Deployment has 0 available replicas for 10+ min (namespace `kagent`).

## Impact

The kagent control plane is down: the operator stops reconciling `Agent`/`ModelConfig`
CRs, the REST/A2A API is unreachable, and the console (which proxies `/api` to the
controller) errors. No effect on the rest of the cluster — kagent is advisory/Phase-1.

## First steps

```bash
kubectl -n kagent get deploy kagent-controller
kubectl -n kagent get pods | grep controller
kubectl -n kagent logs deploy/kagent-controller --tail=80
kubectl -n kagent describe deploy kagent-controller | tail -30
```

## Common causes

| Symptom | Cause |
|---|---|
| `No database connection` / `dial tcp ...:5432` | bundled `kagent-postgresql` is down — `kubectl -n kagent get pods \| grep postgres` |
| `CreateContainerConfigError` | the `kagent-anthropic` ESO Secret is missing — `kubectl -n kagent get es,secret` |
| `Pending` / `Unschedulable` | single-node CPU-request pressure — `kubectl -n kagent describe pod <pod>` |
| `ImagePullBackOff` | `cr.kagent.dev` unreachable or a bad tag — check the egress NetworkPolicy / registry |

## Fix

- Postgres down → `kubectl -n kagent rollout restart deploy/kagent-postgresql`, then the controller.
- Missing secret → confirm Vault `secret/schnappy/ai` holds the key and `kubectl -n kagent get es kagent-anthropic` is `SecretSynced`.
- Otherwise restart: `kubectl -n kagent rollout restart deploy/kagent-controller`.

## Verification

- `kubectl -n kagent get deploy kagent-controller` → AVAILABLE 1
- Alert clears within ~10m
