# ScyllaBackupNeverSucceeded

**Severity:** warning · **For:** 26h

## What fired

A backup task has had no successful run since Scylla Manager last started (its metrics are counted from its start: after an upgrade restarted it, the daily backup has not succeeded once in 26 h).

## How bad

As [ScyllaBackupMissed](ScyllaBackupMissed.md): no fresh snapshot.

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

As [ScyllaBackupMissed](ScyllaBackupMissed.md); the ops playbook scylla-backup-check.yml runs one backup per production cluster and checks its snapshot.

## Verification

A run ends DONE; the alert resolves.
