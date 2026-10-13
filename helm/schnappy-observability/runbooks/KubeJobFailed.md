# KubeJobFailed

**Severity:** warning · **For:** 15m

## What fired

Job `$labels.namespace/$labels.job_name` has failed pods, none succeeded, and nothing still running — it exhausted its `backoffLimit` retries without ever completing. (Derived from the `kube_job_status_*` counters; `kube_job_failed` is emitted only while a job sits in the Failed condition. The `unless` joins are pinned `on(namespace, job_name)` because `kube_job_status_failed` carries a `reason` label the succeeded/active series lack.)

A failed run of a **CronJob** stops firing once a later run of the same CronJob succeeds (its Job was created before `kube_cronjob_status_last_successful_time`): the failed Job stays until `failedJobsHistoryLimit` newer failures push it out, which a recovered CronJob never produces. So a CronJob alert that is still firing means it has not succeeded since that run failed.

## Impact

Depends on the Job. The k6-smoke PostSync hook failing means a deploy's smoke test did not pass — treat as a possibly-broken release. The etcd-backup CronJob (kube-system) failing means no fresh etcd snapshot to the Pi backup store (DR gap). **restore-check-age** (kube-system) failing means a Pi has not restored the backups for two of its turns - production's Postgres, ten's etcd snapshot or the Pis' own backup may no longer restore (see below). velero kopia-maintain, sonarqube-setup, gateway-patch, hyperfoil are advisory or one-shot. After a node reboot, old Jobs left in Failed phase are cosmetic cruft, not an incident.

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

- **An image the registry no longer serves.** `ErrImagePull` / `ImagePullBackOff` with `401 Unauthorized` or `not found` in the pod events, until the Job's `activeDeadlineSeconds`. 2026-09-24: `quay.io/minio/mc` went private and `docker.io/minio/mc` disappeared; etcd-backup (`:latest`, so pulled on every run) failed hourly until it was set to `imagePullPolicy: IfNotPresent` on the copy the node had.

| Symptom in logs | Cause |
|---|---|
| smoke test: checks failed / threshold breached, non-2xx | app endpoint returning errors — check that workload's pods/logs first |
| `403` / `401` from the smoke run | missing RBAC or Keycloak permission for the smoke SA |
| `ErrImagePull` / `ImagePullBackOff` (in pods) | bad tag or registry/NetworkPolicy egress blocked |
| `OOMKilled` (in `describe pod`) | Job memory limit too low |
| etcd-backup: backup-store connection refused | Pi backup-store VIP down — see node-reboot/DR docs |
| restore-check-age: `<pi> STALE` or `last-success missing` | that Pi's restore check failed or did not run - the log above it shows its last-report (which part: POSTGRES, ETCD, TIER0, and why) |
| restore-check-age: an rclone error after `missing or unreadable` | the store itself: credentials (`etcd-backup-store`), or the VIP down |

**restore-check-age, on the Pi whose turn it was** (pi1 the even UTC days, pi2 the odd ones):

```bash
ssh pi1 'systemctl status pi-restore-check.service --no-pager; journalctl -u pi-restore-check --since -2d | tail -40'
# a run now, whatever the day (as the unit runs it):
ssh pi1 'sudo systemd-run --wait --pipe --collect -p EnvironmentFile=/etc/pi-restore-check/env \
  /usr/bin/env PI_RESTORE_ANY_DAY=1 /usr/local/sbin/pi-restore-check.sh'
```

## Verify resolved

Fix the underlying cause, re-run (or re-sync the Argo app), confirm the new Job reaches `1/1` Completions, then delete the stale failed Job to clear the alert:

```bash
kubectl -n $NS delete job $NAME
```

Alert clears within ~15m once no failed Job matches the expr.
