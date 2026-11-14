# VeleroBackupPartiallyFailed

**Severity:** warning · **For:** 5m

## What fired

A Velero backup ended `PartiallyFailed` in the last hour: `increase(velero_backup_partial_failure_total[1h]) > 0`.
It is no failure on the failure counters, so [VeleroScheduledBackupFailed](VeleroScheduledBackupFailed.md) does not
fire; a scheduled backup ending this way is no success either, so
[VeleroDailyBackupMissing](VeleroDailyBackupMissing.md) (26 h) and
[VeleroWeeklyBackupMissing](VeleroWeeklyBackupMissing.md) (8 d) follow if it keeps happening.

## Impact

The backup holds most of the cluster; the items and volumes in its errors are missing from it.

## First steps

```bash
kubectl -n velero get backups.velero.io --sort-by=.status.startTimestamp | tail -5
NAME=<the PartiallyFailed backup>
kubectl -n velero exec "$(kubectl -n velero get pod -l name=velero --field-selector=status.phase=Running -o name | head -1)" -c velero -- /velero backup describe $NAME --details | sed -n '/^Errors:/,/^Warnings:/p'
kubectl -n velero get podvolumebackups -l velero.io/backup-name=$NAME \
  -o custom-columns=P:.status.phase,NS:.spec.pod.namespace,POD:.spec.pod.name,V:.spec.volume,M:.status.message | grep -v Completed
```

## Common causes

| Symptom | Cause | Fix |
|---|---|---|
| `error identifying unique volume path on host` for a Job's pod | the pod ended while the backup read its volumes | label the Job's pod template `velero.io/exclude-from-backup: "true"` (every chart Job and the etcd-backup CronJob carry it since 2026-10-11; `.woodpecker/chart-render-checks.sh` enforces it in platform) |
| `error to expose PVB: error getting client pod ...: pods "..." not found` | a Deployment's pod was replaced while the backup read its volumes (a rollout during the run: masi at 02:01 UTC, 2026-11-13) | since 2026-11-13 the schedules leave pods out, so no volume is read: check that the schedule still does - `kubectl -n velero get schedule velero-schnappy-daily -o jsonpath='{.spec.template.excludedResources}'` (`["pods"]`); run the schedule once to get a clean backup |
| a volume of a running pod failed | node-agent on that node down, or kopia repository trouble | `kubectl -n velero get pod -l name=node-agent`; `kubectl -n velero get backuprepository` |

## Verification

Run the schedule once; it must end `Completed`:

```bash
kubectl -n velero exec "$(kubectl -n velero get pod -l name=velero --field-selector=status.phase=Running -o name | head -1)" -c velero -- /velero backup create --from-schedule velero-full-weekly --wait
```
