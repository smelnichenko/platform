# VeleroWeeklyBackupMissing

**Severity:** warning · **For:** 10m

## What fired

The last fully successful `velero-full-weekly` backup in Prometheus' history is older than 8 days (the schedule runs
Sundays at 03:00 UTC), or there is no history at all. A `PartiallyFailed` backup does not count. The history keeps the
last success across a Velero restart; a Velero gone is [VeleroDown](VeleroDown.md).

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
