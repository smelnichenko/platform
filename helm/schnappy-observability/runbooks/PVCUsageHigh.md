# PVCUsageHigh

**Severity:** warning · **For:** 10m

## What fired

PVC `$labels.persistentvolumeclaim` is using > 80% of its capacity. `PVCUsageCritical` (90%) is next; once full, the workload usually wedges.

## Impact

Heads-up. Specific consumer reactions when full:
- ClickHouse: writes block, fluent-bit's WAL backs up, eventually drops
- Mimir/Tempo: WAL writes fail, recent data lost
- Postgres (CNPG): refuses new writes, app gets `PANIC: could not write to file`
- MinIO: returns 507 Insufficient Storage

## First steps

```bash
kubectl -n $NS get pvc $NAME -o jsonpath='request={.spec.resources.requests.storage} status={.status.capacity.storage}{"\n"}'
kubectl -n $NS exec $POD -- df -h $MOUNT_PATH
# What's eating space?
kubectl -n $NS exec $POD -- du -sh $MOUNT_PATH/* 2>/dev/null | sort -h | tail -10
```

## Common fixes

| Cause | Fix |
|---|---|
| Logs accumulating (CH) | TTL not expiring — `OPTIMIZE TABLE logs.podlogs FINAL` and verify TTL clause |
| Old backups (Velero) | retention policy too long — adjust `--ttl` in BackupSchedule |
| OO sled metadata grew | (OO retired — N/A now) |
| Genuine growth | bump PVC: `kubectl -n $NS patch pvc $NAME -p '{"spec":{"resources":{"requests":{"storage":"<NEW>"}}}}'` (only works with VolumeExpansion-enabled StorageClass) |

## Verify resolved

`kubelet_volume_stats_used_bytes{persistentvolumeclaim=$NAME} / kubelet_volume_stats_capacity_bytes{persistentvolumeclaim=$NAME} < 0.8`.
