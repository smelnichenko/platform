# VeleroDailyBackupMissing

**Severity:** critical · **For:** 10m

## What fired

The last successful `velero-schnappy-daily` backup in Prometheus' history is older than 30h (none ran, or none
succeeded), or there is no history at all (a fresh Prometheus or copy). Velero keeps the last success in memory only;
the history keeps it across a Velero restart, so a restart alone does not fire this. A Velero gone is
[VeleroDown](VeleroDown.md), at once - this alert follows only once the last success is 30h old.

## Impact

Backups are not landing. If the cluster is destroyed now, we lose data from the last known-good backup. No immediate user-facing impact.

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
| Last backup `PartiallyFailed`, its failed PodVolumeBackups say `pods "..." not found` | A pod was deleted while Velero read its volumes (a rollout during the 02:00 UTC run - masi at 02:01, 2026-11-13) | Run the schedule once (below). Since the `velero-skip-ephemeral-volumes` policy no volume is read (emptyDir, hostPath and the API-projected types skipped; Velero holds manifests only - the data's own backups are CNPG's, Scylla Manager's and the Pis'), so check the policy is on the schedule: `kubectl -n velero get schedule velero-schnappy-daily -o jsonpath='{.spec.template.resourcePolicy}'` |
| Last backup `FailedValidation` | The schedule's resource policy ConfigMap missing or invalid | `kubectl -n velero get backups.velero.io <name> -o jsonpath='{.status.validationErrors}'`; sync the `velero` Argo app (it owns the ConfigMap), then run the schedule once |

`exec deploy/velero` is not used here on purpose: the node-agent DaemonSet's pods and dead old server pods carry the
Deployment's selector labels, and kubectl picks the first match - a node-agent pod has no `velero` container. Select
the running server pod by `name=velero`.

## Fix

After the root cause is fixed, run the schedule once:

```bash
kubectl -n velero exec "$(kubectl -n velero get pod -l name=velero --field-selector=status.phase=Running -o name | head -1)" -c velero -- /velero backup create --from-schedule velero-schnappy-daily --wait
```

The backup ends `Completed`; the alert resolves 10 minutes later.

## Verification

- `kubectl -n velero get bsl default -o jsonpath='{.status.phase}'` → `Available`
- the next scheduled run (daily, 02:00 UTC) completes
