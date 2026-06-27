# KubeDeploymentReplicasMismatch

**Severity:** warning · **For:** 15m

## What fired

Deployment `$labels.namespace/$labels.deployment` has had fewer available replicas than desired for 15+ min AND stopped progressing. The `changes(...)==0` guard means this is a *stuck* rollout, not a normal in-flight one — the available count is frozen below spec.

## Impact

Degraded capacity for that workload; if the short ReplicaSet is the new one, the latest deploy never landed and you're running old pods (or fewer than you want). This is the only node, so there's nowhere else to reschedule — a stuck pod stays stuck until the cause is fixed. `KubePodCrashLooping` / `KubePodNotReady` usually fire alongside.

## First steps

```bash
NS=<namespace>; NAME=<deployment>
kubectl -n $NS rollout status deploy/$NAME --timeout=5s     # "Waiting for..." == stuck
kubectl -n $NS get rs | grep "^$NAME-"                      # which RS is short on READY
kubectl -n $NS describe deploy/$NAME | sed -n '/Events/,$p'
# new (short) RS Events tell you why its pods won't come up:
RS=$(kubectl -n $NS get rs --sort-by=.metadata.creationTimestamp -o name | grep "/$NAME-" | tail -1)
kubectl -n $NS describe $RS | sed -n '/Events/,$p'
kubectl -n $NS get pods | grep "$NAME-"      # CrashLoop / ImagePullBackOff / Pending?
```

(Schnappy workloads label with `app.kubernetes.io/name`, not a bare `app=` — grepping the listing by name avoids guessing the selector.)

## Common causes

| Symptom | Cause |
|---|---|
| New pods `CrashLoopBackOff` | bad code/config in last deploy — `kubectl logs --previous`, fix & re-deploy via CD |
| `ImagePullBackOff` on new tag | CD pushed a missing/broken image — check Woodpecker/Kaniko build, confirm tag in registry |
| Pods `Running` but never `Ready` | failing readiness probe (slow start, DB/dep down, mTLS) |
| Pods `Pending` | unschedulable: node out of CPU/mem, quota, or volume not binding |
| Rollout blocked, old pods stay | PodDisruptionBudget won't allow eviction |

On this GitOps cluster a stuck rollout is most often a bad image from the last CD run. Check the Argo app and the running tag: `kubectl -n $NS get deploy/$NAME -o jsonpath='{.spec.template.spec.containers[*].image}'`. Fix in git / re-trigger CD — do not `kubectl edit` the image (Argo reverts it).

## Verify resolved

`kubectl -n $NS rollout status deploy/$NAME` prints "successfully rolled out", and available == desired:
`kubectl -n $NS get deploy/$NAME` shows READY `N/N` matching. Alert clears within ~15m.
