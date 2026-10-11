# VeleroBackupFailing

**Severity:** warning · **For:** 5m

## What fired

A Velero backup ended in error within the last hour — `increase(velero_backup_failure_total[1h]) > 0`.

## Impact

The most recent backup is unusable. A scheduled one also fires [VeleroScheduledBackupFailed](VeleroScheduledBackupFailed.md); with no daily success in
30h [VeleroDailyBackupMissing](VeleroDailyBackupMissing.md) follows, and then no recent restore point exists.

## First steps

```bash
kubectl -n velero get backup --sort-by=.metadata.creationTimestamp | tail -5
LATEST=$(kubectl -n velero get backup --sort-by=.metadata.creationTimestamp -o name | tail -1)
kubectl -n velero describe $LATEST | tail -30
kubectl -n velero logs deploy/velero --tail=80 | grep -iE 'error|fail' | tail -20
```

## Common causes

| Symptom | Cause |
|---|---|
| `BSL unavailable` | backup store (versitygw) down, credentials wrong/expired (`secret/schnappy/velero` in Vault) |
| `volume snapshot timeout` | CSI driver issue, or the source PV is huge and exceeds backup-window |
| `failed to upload` to S3 | Network-policy egress blocking velero → versitygw, or the bucket policy changed |

## Verify resolved

Run the failed schedule once; it must end `Completed` with no errors:

```bash
kubectl -n velero exec deploy/velero -c velero -- /velero backup create --from-schedule velero-schnappy-daily --wait
```

## Related

A `PartiallyFailed` backup is [VeleroBackupPartiallyFailed](VeleroBackupPartiallyFailed.md); the 30h watchdog is
[VeleroDailyBackupMissing](VeleroDailyBackupMissing.md).
