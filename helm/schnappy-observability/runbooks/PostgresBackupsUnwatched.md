# PostgresBackupsUnwatched

**Severity:** warning · **For:** 30m

## What fired

Prometheus has no `cnpg_cluster_condition` series: no CloudNativePG Cluster's status is scraped. Kube-state-metrics publishes these series from its custom-resource config (`kube-state-metrics-custom-resources.yaml`).

## How bad

Nothing is broken by this alone, but `PostgresArchivingFailed`, `PostgresBackupFailed`, `PostgresBackupStuck`, `PostgresBackupMissed` and `PostgresBackupNeverSucceeded` all read those series. While they are gone, none of these alerts can fire, whatever the backups do.

## First steps

```bash
kubectl -n schnappy-infra get pods -l app.kubernetes.io/name=kube-state-metrics
kubectl -n schnappy-infra logs deploy/schnappy-kube-state-metrics --since=1h | grep -iE 'custom|cnpg|error' | tail -20
kubectl get clusters.postgresql.cnpg.io -A
```

## Root-cause investigation

| Symptom | Cause |
|---|---|
| kube-state-metrics not running or crash-looping | its pod; a bad custom-resource config fails its start |
| running, its log naming the custom-resource config or `postgresql.cnpg.io` | the config no longer matches CloudNativePG's CRD (a CNPG upgrade renamed a field or a version), or its RBAC lacks the `clusters` resource |
| running, no error, no Cluster listed by kubectl | no CNPG Cluster exists - expected only where no Postgres runs |
| everything above fine | Prometheus not scraping kube-state-metrics (its ServiceMonitor, a NetworkPolicy) |

## Fix

Fix the config or the scrape; the chart's checksum restarts kube-state-metrics on a config change.

## Verification

`cnpg_cluster_condition` returns one series per Cluster and condition; the alert resolves.
