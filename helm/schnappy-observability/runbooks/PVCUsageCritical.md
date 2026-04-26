# PVCUsageCritical

**Severity:** critical · **For:** 5m

## What fired

PVC `$labels.persistentvolumeclaim` is at > 90% capacity. Workload may wedge within minutes.

## Impact

See PVCUsageHigh runbook — same consumers, but now imminent. ClickHouse will block writes, fluent-bit will buffer until its own disk fills, Postgres will refuse writes.

## First steps (fast)

```bash
# Confirm + see what's using it
kubectl -n $NS exec $POD -- df -h
kubectl -n $NS exec $POD -- du -sh /var/lib/$DIR/* 2>/dev/null | sort -h | tail -10

# Quick bump if storage class supports online expansion
kubectl -n $NS patch pvc $NAME -p '{"spec":{"resources":{"requests":{"storage":"<larger>"}}}}'
kubectl -n $NS get pvc $NAME -o jsonpath='{.status.conditions}{"\n"}'
```

## Recovery if already full

| Workload | Recovery |
|---|---|
| ClickHouse | drop oldest partitions: `clickhouse-client --query 'ALTER TABLE logs.podlogs DROP PARTITION YYYYMMDD'` |
| Postgres (CNPG) | promote a fresh replica with bigger disk, then failover |
| Velero | `velero backup delete --confirm --selector ...` to free space |
| Generic | identify largest files (`du`), delete or rotate, verify writes resume |

## Verify resolved

PVC usage < 90% AND consumer pod readiness back to `1/1` (writes succeeding again).
