# ScyllaBackupMissed

**Severity:** warning · **For:** 1h

## What fired

A live backup task (the operator's ScyllaDBManagerTask, by its Manager ID) has not succeeded for 26 h (`time() - scylla_manager_scheduler_last_success{type="backup"} > 26 * 3600`, the live tasks only - Manager keeps a deleted task's last success).

## How bad

The newest ScyllaDB snapshot in the store is older than a day.

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

Fix the cause, then run it now: `$M sctool start -c <cluster> backup/<task>` and follow `sctool progress`.

## Verification

`sctool tasks` shows the task DONE with a fresh last success; the alert resolves.
