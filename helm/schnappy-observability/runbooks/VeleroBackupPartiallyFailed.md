# VeleroBackupPartiallyFailed

**Severity:** warning · **For:** 5m

## What fired

A Velero backup ended `PartiallyFailed` in the last hour: `increase(velero_backup_partial_failure_total[1h]) > 0`.
Velero leaves `velero_backup_last_status` at 1 for it, so no other alert sees it. A weekly backup that keeps
ending this way also fires [VeleroWeeklyBackupMissing](VeleroWeeklyBackupMissing.md).

## Impact

The backup holds most of the cluster; the items and volumes in its errors are missing from it.

## First steps

```bash
kubectl -n velero get backups --sort-by=.status.startTimestamp | tail -5
NAME=<the PartiallyFailed backup>
kubectl -n velero exec deploy/velero -c velero -- /velero backup describe $NAME --details | sed -n '/^Errors:/,/^Warnings:/p'
kubectl -n velero get podvolumebackups -l velero.io/backup-name=$NAME \
  -o custom-columns=P:.status.phase,NS:.spec.pod.namespace,POD:.spec.pod.name,V:.spec.volume,M:.status.message | grep -v Completed
```

## Common causes

| Symptom | Cause | Fix |
|---|---|---|
| `error identifying unique volume path on host` for a Job's pod | the pod ended while the backup read its volumes | label the Job's pod template `velero.io/exclude-from-backup: "true"` (every chart Job and the etcd-backup CronJob carry it since 2026-10-11; `.woodpecker/chart-render-checks.sh` enforces it in platform) |
| a volume of a running pod failed | node-agent on that node down, or kopia repository trouble | `kubectl -n velero get pod -l name=node-agent`; `kubectl -n velero get backuprepository` |

## Verification

Run the schedule once; it must end `Completed`:

```bash
kubectl -n velero exec deploy/velero -c velero -- /velero backup create --from-schedule velero-full-weekly --wait
```
