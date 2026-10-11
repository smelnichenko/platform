# VeleroDown

**Severity:** critical · **For:** 15m

## What fired

No Velero server answered its metrics scrape for 15 minutes: `absent(up{namespace="velero", container="velero"} == 1)`
- the pod is down or failing, or there is no target at all (the Deployment scaled to 0 or deleted).

## Impact

No backup runs. The age alerts ([VeleroDailyBackupMissing](VeleroDailyBackupMissing.md),
[VeleroWeeklyBackupMissing](VeleroWeeklyBackupMissing.md)) read the last success from Prometheus' history, so they stay
quiet until that success is older than their period - this alert is the one that fires at once.

## First steps

```bash
kubectl -n velero get deploy velero
kubectl -n velero get pod -l app.kubernetes.io/name=velero -o wide
kubectl -n velero logs deploy/velero --tail=80
kubectl -n argocd get application velero -o jsonpath='{.status.sync.status} {.status.health.status}{"\n"}'
```

## Fix

Bring the Deployment back through Argo (the velero Application), never by hand. Once the pod is Ready the alert
resolves; a Velero restart sets its in-memory status back - the next scheduled backup proves it.
