# VeleroBackupFailing

**Severity:** warning · **For:** 5m

## What fired

A Velero backup ended in error within the last hour — `increase(velero_backup_failure_total[1h]) > 0`.

## Impact

The most recent backup is unusable. If `VeleroBSLUnavailable` follows (no successful backup in 30h), no recent restore point exists.

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
| `BSL unavailable` | MinIO down, credentials wrong/expired (`secret/schnappy/velero` in Vault) |
| `volume snapshot timeout` | CSI driver issue, or the source PV is huge and exceeds backup-window |
| `partial failure` (some resources skipped) | check `kubectl get backup $NAME -o yaml | yq '.status.errors'` |
| `failed to upload` to S3 | Network-policy egress blocking velero → MinIO, or MinIO bucket policy changed |

## Verify resolved

Next scheduled run completes `Phase: Completed` with no errors.

```bash
kubectl -n velero create backup test-recovery-$(date +%s) --include-namespaces=schnappy-test --wait
```

## Related

If this becomes chronic, see `VeleroBSLUnavailable` (the 30h watchdog).
