# KagentToolsCrashLooping

**Severity:** warning · **For:** 5m

## What fired

A `kagent-tools` pod restarted more than 3 times in 15 min (namespace `kagent`).

## Impact

`kagent-tools` is the MCP tool executor that runs every agent's kubectl/k8s calls
(under the read-only `kagent-tools` ServiceAccount). While it's down, agents can still
answer from context but cannot read live cluster state, so diagnoses degrade. Advisory
plane only.

## First steps

```bash
kubectl -n kagent logs deploy/kagent-tools --previous --tail=120
kubectl -n kagent get pods | grep tools
kubectl -n kagent describe pod "$(kubectl -n kagent get pod -o name | grep tools | head -1)" | sed -n '/Last State/,/Ready/p'
```

## Common causes

| Symptom | Cause |
|---|---|
| `forbidden` RBAC floods | the read-only role/binding drifted or was pruned — `kubectl get clusterrole kagent-tools-read-role` |
| `unknown flag --read-only` | chart/app version skew on the `tools.args` value |
| `OOMKilled` | tools memory limit (256Mi) too low |
| connection refused to controller | controller is down (see `KagentControllerDown`) |

## Fix

- Missing read-role → Argo `selfHeal: true` restores the ClusterRole/Binding automatically; force it with `kubectl -n argocd annotate app kagent argocd.argoproj.io/refresh=hard --overwrite`.
- OOM → raise `kagent-tools.resources.limits.memory` in `clusters/production/kagent/values.yaml`.
- Otherwise `kubectl -n kagent rollout restart deploy/kagent-tools`.

## Verification

- Restart count stops climbing: `kubectl -n kagent get pods | grep tools`
- An agent k8s query (e.g. "describe the failing pod") returns live data again
