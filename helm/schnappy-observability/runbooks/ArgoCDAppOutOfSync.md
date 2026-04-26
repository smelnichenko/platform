# ArgoCDAppOutOfSync

**Severity:** warning · **For:** 30m

## What fired

Argo CD `Application/$labels.name` reported `sync_status != Synced` for 30+ min. Live cluster state has drifted from the rendered manifests in git.

## Impact

Resources won't match git. If `selfHeal: true` is set, Argo retries indefinitely (CPU + log noise). If pruning is on, real changes might be reverted.

## First steps

```bash
kubectl -n argocd get application $APP -o jsonpath='sync={.status.sync.status} health={.status.health.status} phase={.status.operationState.phase} cond={.status.conditions}{"\n"}'
kubectl -n argocd exec argocd-application-controller-0 -- argocd app diff $APP --core
kubectl -n argocd get application $APP -o jsonpath='{range .status.resources[?(@.status=="OutOfSync")]}{.kind}/{.name}{"\n"}{end}'
```

## Common causes

| Symptom | Cause |
|---|---|
| `status: Unknown` + `ComparisonError` | repo unreachable — check NetworkPolicy egress, repo-server logs |
| `app diff` empty but `OutOfSync` flag stays | v3.3.x `ServerSideApply=true` cosmetic bug — drop SSA on the App, prefer CSA |
| Real diff in spec.replicas | HPA-managed — add `/spec/replicas` to `ignoreDifferences` |
| Stuck `phase: Running` for hours | wedged op — `kubectl patch ... operation=null,operationState=null` |
| Resource missing on cluster | sync wave dependency or NetworkPolicy blocking |

## Verify resolved

`kubectl -n argocd get application $APP -o jsonpath='{.status.sync.status} {.status.health.status}'` returns `Synced Healthy`.
