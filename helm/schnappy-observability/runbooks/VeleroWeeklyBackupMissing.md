# VeleroWeeklyBackupMissing

**Severity:** warning · **For:** 10m

## What fired

No fully successful `velero-full-weekly` backup in the last 8 days (the schedule runs Sundays at 03:00 UTC). A
`PartiallyFailed` backup does not count. The alert also fires when Velero is down (no metrics at all). Velero
keeps the last success in memory only, so for 8 days after a Velero start the alert waits: a restart alone does
not fire it.

## Impact

The cluster-wide restore point (every namespace) is older than a week or incomplete. The daily backup
(`schnappy-production` only) is watched by [VeleroDailyBackupMissing](VeleroDailyBackupMissing.md).

## First steps

```bash
kubectl -n velero get backups --sort-by=.status.startTimestamp | grep full-weekly | tail -3
kubectl -n velero get schedule velero-full-weekly
```

A `PartiallyFailed` run: see [VeleroBackupPartiallyFailed](VeleroBackupPartiallyFailed.md). A `Failed` run: see
[VeleroScheduledBackupFailed](VeleroScheduledBackupFailed.md).

## Fix

After the cause is fixed, run the schedule once (about 70 minutes):

```bash
kubectl -n velero exec deploy/velero -c velero -- /velero backup create --from-schedule velero-full-weekly --wait
```

## Verification

The backup ends `Completed`; the alert resolves 10 minutes later.
