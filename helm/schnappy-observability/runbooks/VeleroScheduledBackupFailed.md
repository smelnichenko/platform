# VeleroScheduledBackupFailed

**Severity:** critical · **For:** 10m

## What fired

The last backup of a Velero schedule failed: `velero_backup_last_status{schedule!=""} == 0`. Often the
BackupStorageLocation is `Unavailable`. A `PartiallyFailed` backup does not fire it (Velero leaves the
status at 1); that is [VeleroBackupPartiallyFailed](VeleroBackupPartiallyFailed.md).

## Impact

Backups are not landing. If the cluster is destroyed now, the data since the last good backup is lost. No
immediate user-facing impact.

## First steps

```bash
kubectl -n velero get bsl default -o jsonpath='{.status.phase} {.status.message}{"\n"}'
kubectl -n velero get schedules
kubectl -n velero get backups --sort-by=.status.startTimestamp | tail -5
```

## Common causes

| Symptom | Cause | Fix |
|---|---|---|
| `Unavailable: ... 500 internal error` | Pi backup store (versitygw) broken | Check `systemctl status versitygw` on Pi1+Pi2 |
| `NoSuchBucket` | bucket got wiped | `mc mb vip/velero` on a Pi |
| No recent Backup objects | Schedule disabled or paused | `kubectl -n velero get schedule velero-schnappy-daily -o yaml` |
| Kopia-maintain jobs all Error | BackupRepository CRs reference missing kopia paths | `kubectl -n velero delete backuprepository --all` (recreated lazily) |

## Fix

After the root cause is fixed, run the failed schedule once more. The backup carries the schedule's label, so
the metric (and the alert) follows it:

```bash
kubectl -n velero exec deploy/velero -c velero -- /velero backup create --from-schedule velero-schnappy-daily --wait
```

## Verification

- `kubectl -n velero get bsl default -o jsonpath='{.status.phase}'` → `Available`
- the backup above ends `Completed`; the alert resolves 10 minutes later
- a Velero restart sets every schedule's status back to 1 (success) until its next run. A resolve right after a
  restart proves nothing; the schedule's next run does
