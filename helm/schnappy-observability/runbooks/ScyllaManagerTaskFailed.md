# ScyllaManagerTaskFailed

**Severity:** warning

## What fired

A backup or repair run of Scylla Manager ended ERROR or ABORTED within the last hour (`increase(scylla_manager_scheduler_run_total{type=~"backup|repair", status=~"ERROR|ABORTED"}[1h]) > 0`; healthchecks are not counted).

## How bad

That run's snapshot (backup) or repair did not happen; repeated failures turn into [ScyllaBackupMissed](ScyllaBackupMissed.md).

## First steps

```bash
M="kubectl -n scylla-manager exec deploy/scylla-manager -c scylla-manager --"
$M sctool cluster list
$M sctool tasks -c <cluster from the alert>
$M sctool progress -c <cluster> <type>/<task name>      # the last run: its error per host
kubectl -n scylla-manager logs deploy/scylla-manager --since=6h | grep -iE 'error|fail' | tail -20
```

## Root-cause investigation

| Symptom | Cause |
|---|---|
| `agent not available`, `connection refused` to a node's 10001 | the ScyllaDB pod's manager agent down or not yet registered (after a pod restart) |
| `AccessDenied`, `NoSuchBucket` in a backup | the agents' store credentials (`scylla-agent-config-secret`) or the `scylla-backups` bucket |
| `context deadline exceeded` uploading | the Pi backup store slow or down |
| the task missing from `sctool tasks` | the operator did not register it: its ScyllaDBManagerTask resource (`kubectl get scylladbmanagertasks -A`) and the operator's log |

## Fix

Fix the cause, then `$M sctool start -c <cluster> <type>/<task>`.

## Verification

The next run ends DONE.
