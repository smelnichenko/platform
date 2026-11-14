# VeleroBackupFailing

**Severity:** warning · **For:** 5m

## What fired

An ad-hoc Velero backup (one with no schedule: `velero backup create` by hand) ended in error within the last
hour — `increase(velero_backup_failure_total{schedule=""}[1h]) > 0`. A scheduled backup's failure is
[VeleroScheduledBackupFailed](VeleroScheduledBackupFailed.md) alone.

## Impact

That backup is unusable; the scheduled ones are not affected by it (their own alerts:
[VeleroScheduledBackupFailed](VeleroScheduledBackupFailed.md), and [VeleroDailyBackupMissing](VeleroDailyBackupMissing.md)
26h after the last daily success).

## First steps

```bash
kubectl -n velero get backups.velero.io --sort-by=.metadata.creationTimestamp | tail -5
LATEST=$(kubectl -n velero get backups.velero.io --sort-by=.metadata.creationTimestamp -o name | tail -1)
kubectl -n velero describe $LATEST | tail -30
POD=$(kubectl -n velero get pod -l name=velero --field-selector=status.phase=Running -o name | head -1)  # the server's
kubectl -n velero logs "$POD" -c velero --tail=80 | grep -iE 'error|fail' | tail -20
```

## Common causes

| Symptom | Cause |
|---|---|
| `BSL unavailable` | backup store (versitygw) down, credentials wrong/expired (`secret/schnappy/velero` in Vault) |
| `volume snapshot timeout` | CSI driver issue, or the source PV is huge and exceeds backup-window |
| `failed to upload` to S3 | Network-policy egress blocking velero → versitygw, or the bucket policy changed |

## Verify resolved

Run the backup again as it was made (its spec: `kubectl -n velero get backups.velero.io <name> -o yaml`); it must end
`Completed` with no errors. The alert resolves an hour after the failure either way.

## Related

A `PartiallyFailed` backup is [VeleroBackupPartiallyFailed](VeleroBackupPartiallyFailed.md); the 26h watchdog is
[VeleroDailyBackupMissing](VeleroDailyBackupMissing.md).
