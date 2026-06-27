# KubeDaemonSetUnavailable

**Severity:** warning · **For:** 15m

## What fired

DaemonSet `$labels.namespace/$labels.daemonset` has `kube_daemonset_status_number_unavailable > 0`. On this single-node cluster (`ten`) desired is 1 per DS, so the one pod is not Ready — the DS is effectively down.

## Impact

Depends on which DS. **Cilium is the serious one**: it is the CNI with kube-proxy-replacement, so a broken Cilium pod wedges all pod networking — treat as high urgency despite warning severity. Others degrade a subsystem: fluent-bit → no logs to ClickHouse, velero/node-agent → fs-backup volume backups/restores stall, cilium-envoy → L7 proxy/policy, istio-cni → new pods fail to get mesh wiring.

## First steps

```bash
kubectl get ds -A | awk 'NR==1 || $3!=$5'            # which DS is short (DESIRED != READY)
NS=<namespace>; NAME=<daemonset>
kubectl -n $NS get pods -o wide | grep "$NAME-"
POD=$(kubectl -n $NS get pods -o name | grep "/$NAME-" | head -1)
kubectl -n $NS describe $POD | sed -n '/Events/,$p'
kubectl -n $NS logs $POD --tail=120
kubectl -n kube-system exec ds/cilium -- cilium status --brief   # if NAME is cilium
```

## Common causes

| Symptom | Cause |
|---|---|
| `ImagePullBackOff` / `ErrImagePull` | bad tag or registry/Nexus unreachable |
| `Pending` + `disk-pressure` / `Insufficient cpu` | node under resource or disk pressure — see PVCUsageCritical |
| Readiness/liveness probe failing in `describe` | bad config rollout (Cilium/fluent-bit) — check the recent chart change |
| `CreateContainerError` on a hostPath/privileged mount | host path missing or mount denied |
| Cilium pod not Ready, `cilium status` red | networking wedged cluster-wide — highest priority |
| Old `Failed`/`Succeeded` pod after a reboot | cosmetic cruft, shadowed by a healthy pod — ignore |

## Fix

Permanent fixes go through git → Argo CD, not `kubectl edit`. Bad config rollout → revert/fix the values in the chart, commit, let Argo sync. Image pull → fix the tag or restore the registry. Resource/disk pressure → free space, then `kubectl -n $NS delete $POD` to reschedule.

## Verify resolved

`kubectl get ds -n $NS $NAME` shows DESIRED == READY == AVAILABLE and `number_unavailable` back to 0. For Cilium, `cilium status` is all green and test pods get networking.
