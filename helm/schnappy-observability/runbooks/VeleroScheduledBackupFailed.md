# VeleroScheduledBackupFailed

**Severity:** critical · **For:** 1m

## What fired

A backup of a Velero schedule failed, or failed validation, in the last hour: its schedule's
`velero_backup_failure_total` or `velero_backup_validation_failure_total` rose (or was born above 0 on a
new Velero pod). Often the BackupStorageLocation is `Unavailable`. A `PartiallyFailed` backup is
[VeleroBackupPartiallyFailed](VeleroBackupPartiallyFailed.md).

It fires for the hour after the failure and then resolves on its own, whatever happened since: a resolve
is not a fix. A failure that lasts is held by [VeleroDailyBackupMissing](VeleroDailyBackupMissing.md)
(26 h after the last success) until a backup succeeds; the weekly's by
[VeleroWeeklyBackupMissing](VeleroWeeklyBackupMissing.md) (8 d).

## Impact

Velero holds the cluster's manifests only (no volume data: each store has its own backup or none - infra's
`clusters/production/velero/values.yaml`). Rebuilding the cluster would start from the last good backup's
manifests. No immediate user-facing impact.

## First steps

```bash
kubectl -n velero get bsl default -o jsonpath='{.status.phase} {.status.message}{"\n"}'
kubectl -n velero get schedules
kubectl -n velero get backups.velero.io --sort-by=.status.startTimestamp | tail -5
```

## Common causes

| Symptom | Cause | Fix |
|---|---|---|
| `Unavailable: ... 500 internal error` | Pi backup store (versitygw) broken | Check `systemctl status versitygw` on Pi1+Pi2 |
| `NoSuchBucket` | bucket got wiped | `mc mb vip/velero` on a Pi |
| No recent Backup objects | Schedule disabled or paused | `kubectl -n velero get schedule velero-schnappy-daily -o yaml` |
| Kopia-maintain jobs all Error | BackupRepository CRs reference missing kopia paths | `kubectl -n velero delete backuprepository --all` (recreated lazily) |
| Last backup `FailedValidation` | The schedule's template refused (a namespace pattern, a resource name, a field Velero does not take) | `kubectl -n velero get backups.velero.io <name> -o jsonpath='{.status.validationErrors}'`; fix the schedule in infra's `clusters/production/velero/values.yaml` |

## Fix

After the root cause is fixed, run the failed schedule once more - `<schedule>` is the alert's `schedule`
label (`velero-schnappy-daily` or `velero-full-weekly`):

```bash
kubectl -n velero exec "$(kubectl -n velero get pod -l name=velero --field-selector=status.phase=Running -o name | head -1)" -c velero -- /velero backup create --from-schedule <schedule> --wait
```

## Verification

- `kubectl -n velero get bsl default -o jsonpath='{.status.phase}'` → `Available`
- the backup above ends `Completed` - that is the proof. The alert does not follow it: it resolves an hour after
  the failure either way
- the schedule's next run ends `Completed` (`kubectl -n velero get backups.velero.io --sort-by=.status.startTimestamp | tail -3`)
