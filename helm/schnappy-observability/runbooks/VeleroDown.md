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
# the server's pods only (an old Completed one too, named by its prefix): the node-agent's carry the Deployment's selector
# labels too (logs deploy/velero picked one)
kubectl -n velero get pod -l name=velero -o wide
# the running server pod's logs (an old Completed pod also carries name=velero: --previous stopped at it)
POD=$(kubectl -n velero get pod -l name=velero --field-selector=status.phase=Running -o name | head -1)
kubectl -n velero logs "$POD" -c velero --tail=80
kubectl -n velero logs "$POD" -c velero --tail=80 --previous   # a crash loop: the run before
kubectl -n argocd get application velero -o jsonpath='{.status.sync.status} {.status.health.status}{"\n"}'
```

## Fix

Bring the Deployment back through Argo (the velero Application), never by hand. Once the pod is Ready the alert
resolves; a Velero restart sets its in-memory status back - the next scheduled backup proves it.
