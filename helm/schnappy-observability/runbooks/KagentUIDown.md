# KagentUIDown

**Severity:** warning · **For:** 10m

## What fired

The `kagent-ui` Deployment has 0 available replicas for 10+ min (namespace `kagent`).

## Impact

The Next.js console is unreachable. oauth2-proxy proxies to it after login, so a user
may authenticate at Keycloak and then hit a 502. The controller/tools/agents keep
running — this is the operator console only.

## First steps

```bash
kubectl -n kagent get deploy kagent-ui
kubectl -n kagent logs deploy/kagent-ui --tail=80
kubectl -n kagent describe deploy kagent-ui | tail -30
```

## Common causes

| Symptom | Cause |
|---|---|
| `Pending` / `Unschedulable` | single-node CPU-request pressure |
| `OOMKilled` | UI memory limit (1Gi) too low under load |
| CrashLoop on start | bad image tag / config, or `cr.kagent.dev` egress blocked |
| 502 from oauth2-proxy while the UI pod is Running | `UPSTREAM_URL` mismatch (should be `http://kagent-ui:8080`) |

## Fix

- Resource → free node capacity (the UI is `ui.replicas: 1`).
- OOM → raise `ui.resources.limits.memory` in `clusters/production/kagent/values.yaml`.
- Otherwise `kubectl -n kagent rollout restart deploy/kagent-ui`.

## Verification

- `kubectl -n kagent get deploy kagent-ui` → AVAILABLE 1
- The console loads after Keycloak login
