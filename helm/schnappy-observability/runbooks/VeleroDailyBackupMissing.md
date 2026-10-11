# VeleroDailyBackupMissing

**Severity:** critical · **For:** 10m

## What fired

No successful `velero-schnappy-daily` backup in the last 30h (none ran, or none succeeded), or Velero is down (no
metrics at all). Velero keeps the last success in memory only, so for 30h after a Velero start the alert waits:
a restart alone does not fire it.

## Impact

Backups are not landing. If the cluster is destroyed now, we lose data from the last known-good backup. No immediate user-facing impact.

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

After the root cause is fixed, run the schedule once:

```bash
kubectl -n velero exec deploy/velero -c velero -- /velero backup create --from-schedule velero-schnappy-daily --wait
```

The backup ends `Completed`; the alert resolves 10 minutes later.

## Verification

- `kubectl -n velero get bsl default -o jsonpath='{.status.phase}'` → `Available`
- the next scheduled run (daily, 02:00 UTC) completes
