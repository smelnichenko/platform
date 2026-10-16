# ScyllaBackupsUnwatched

**Severity:** warning · **For:** 30m

## What fired

Scylla Manager is scraped, but no ScyllaDBManagerTask of type Backup is listed by kube-state-metrics (`scylladb_manager_task_info{task_type="Backup"}` absent). Kube-state-metrics publishes that series from its custom-resource config (`kube-state-metrics-custom-resources.yaml`).

## How bad

Nothing is broken by this alone, but `ScyllaBackupMissed` and `ScyllaBackupNeverSucceeded` count only the backup tasks that series lists. Without it, neither alert can fire, whatever the backups do.

## First steps

```bash
kubectl get scylladbmanagertasks.scylla.scylladb.com -A
kubectl -n schnappy-infra get pods -l app.kubernetes.io/component=kube-state-metrics
kubectl -n schnappy-infra logs deploy/schnappy-kube-state-metrics --since=1h | grep -iE 'custom|scylla|error' | tail -20
```

## Root-cause investigation

| Symptom | Cause |
|---|---|
| no backup ScyllaDBManagerTask listed by kubectl | the task was deleted or never created (the ScyllaDBCluster's values): Scylla is not backed up at all |
| tasks listed, kube-state-metrics' log naming its custom-resource config or `scylla.scylladb.com` | the config no longer matches the operator's CRD (an operator upgrade moved a field or the version), or its RBAC lacks the resource |
| tasks listed, no error | Prometheus not scraping kube-state-metrics (`PostgresBackupsUnwatched` would fire too) |

## Fix

Recreate the backup task through the cluster's values, or fix the config or the scrape. The chart's checksum restarts kube-state-metrics on a config change.

## Verification

`scylladb_manager_task_info{task_type="Backup"}` returns the backup task; the alert resolves.
