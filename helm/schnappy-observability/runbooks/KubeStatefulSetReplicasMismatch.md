# KubeStatefulSetReplicasMismatch

**Severity:** warning · **For:** 15m

## What fired

StatefulSet `$labels.namespace/$labels.statefulset` has had fewer ready replicas than desired for 15m and stopped progressing (no change in ready count over 10m). StatefulSets this can fire on include ClickHouse, ScyllaDB (scylla-operator), the SonarQube Postgres, Prometheus/Alertmanager, the Woodpecker server/agent, and the Argo CD application-controller. Kafka does **not** count — Strimzi runs it as a StrimziPodSet, not a StatefulSet, so `kube_statefulset_*` never sees it.

## Impact

The set is down a pod. Every workload here runs `replicas: 1` on this single node, so one not-ready ordinal usually means that data service is fully down, not just degraded. StatefulSet pods also roll **ordered**, one ordinal at a time, so a stuck ordinal N blocks every higher ordinal — the cause is almost always one specific pod.

## First steps

```bash
NS=<namespace>; STS=<statefulset>
kubectl -n $NS get sts $STS -o jsonpath='desired={.spec.replicas} ready={.status.readyReplicas}{"\n"}'
# find the not-ready ordinal — that is the blocker
kubectl -n $NS get pods | grep "$STS-"
POD=$STS-N   # the stuck ordinal
kubectl -n $NS describe pod $POD | sed -n '/Events/,$p'
kubectl -n $NS logs $POD --tail=120
```

## Common causes

| Symptom | Cause |
|---|---|
| Pod `Pending`, PVC unbound | volume not provisioned — `kubectl -n $NS get pvc`, check storage class |
| Disk full on the data volume | PVC at capacity — cross-check **PVCUsageCritical**, expand the PVC |
| `CrashLoopBackOff` | bad config, corrupt data dir, or failed schema migration — read logs |
| `0/1 ready`, process up | readiness gate unmet (init/bootstrap not complete) |
| `ImagePullBackOff` | bad tag or registry unreachable — check NetworkPolicy egress |
| ScyllaDB | operator-driven — check the **ScyllaCluster CR** + **scylla-operator logs**, not `kubectl rollout` |

Single-node cluster (`ten`): "reschedule elsewhere" is never an option, so a node-level resource or volume problem is a cluster problem. CNPG Postgres is **not** a StatefulSet — ignore it here.

## Verify resolved

`kubectl -n $NS get sts $STS` shows ready == desired and every ordinal `1/1 Running`. Alert clears after 15m with all replicas ready.
