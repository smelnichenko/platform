# KubeJobFailed

**Severity:** warning · **For:** 15m

## What fired

Job `$labels.namespace/$labels.job_name` has failed pods, none succeeded, and nothing still running — it exhausted its `backoffLimit` retries without ever completing. (This KSM build omits the `kube_job_failed` condition metric, so the expr is derived from `kube_job_status_failed/succeeded/active` counts.)

## Impact

Depends on the Job. The k6-smoke PostSync hook failing means a deploy's smoke test did not pass — treat as a possibly-broken release. The etcd-backup CronJob (kube-system) failing means no fresh etcd snapshot to Pi MinIO (DR gap). velero kopia-maintain, sonarqube-setup, gateway-patch, hyperfoil are advisory or one-shot. After a node reboot, old Jobs left in Failed phase are cosmetic cruft, not an incident.

## First steps

```bash
# Find the failed Job (not Complete, 0 completions)
kubectl get jobs -A | grep -v -E 'Complete|COMPLETIONS'
NS=<namespace>; NAME=<job_name>

# Its pods, then logs (current + crashed attempt)
kubectl -n $NS get pods -l job-name=$NAME
POD=$(kubectl -n $NS get pod -l job-name=$NAME -o name | head -1)
kubectl -n $NS logs $POD
kubectl -n $NS logs $POD --previous
kubectl -n $NS describe job $NAME | sed -n '/Events/,$p'
```

The k6 PostSync hook uses `hook-delete-policy: BeforeHookCreation`, so a failed Job and its pods are NOT cleaned up on failure — they linger (up to the 24h `ttlSecondsAfterFinished`) for inspection.

## Common causes

| Symptom in logs | Cause |
|---|---|
| smoke test: checks failed / threshold breached, non-2xx | app endpoint returning errors — check that workload's pods/logs first |
| `403` / `401` from the smoke run | missing RBAC or Keycloak permission for the smoke SA |
| `ErrImagePull` / `ImagePullBackOff` (in pods) | bad tag or registry/NetworkPolicy egress blocked |
| `OOMKilled` (in `describe pod`) | Job memory limit too low |
| etcd-backup: MinIO connection refused | Pi MinIO VIP down — see node-reboot/DR docs |

## Verify resolved

Fix the underlying cause, re-run (or re-sync the Argo app), confirm the new Job reaches `1/1` Completions, then delete the stale failed Job to clear the alert:

```bash
kubectl -n $NS delete job $NAME
```

Alert clears within ~15m once no failed Job matches the expr.
