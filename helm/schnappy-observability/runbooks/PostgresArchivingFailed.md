# PostgresArchivingFailed

**Severity:** critical · **For:** 15m

## What fired

CloudNativePG reports the Cluster's `ContinuousArchiving` condition False: WAL segments are not reaching the backup store (`cnpg_cluster_condition{type="ContinuousArchiving"} == 0`, from kube-state-metrics).

## How bad

Point-in-time recovery stops at the last archived segment, and `pg_wal` fills the data volume until Postgres stops accepting writes. Act within hours.

## First steps

```bash
NS=<namespace from the alert>; C=<cluster from the alert>
kubectl -n $NS get clusters.postgresql.cnpg.io $C -o jsonpath='{range .status.conditions[*]}{.type}={.status} {.reason}: {.message}{"\n"}{end}'
kubectl -n $NS get clusters.postgresql.cnpg.io $C -o jsonpath='{.status.lastSuccessfulBackup} {.status.lastFailedBackup}{"\n"}'
kubectl -n $NS get backups.postgresql.cnpg.io --sort-by=.metadata.creationTimestamp | tail -5
kubectl -n $NS logs $(kubectl -n $NS get clusters.postgresql.cnpg.io $C -o jsonpath='{.status.currentPrimary}') -c postgres --since=2h \
  | grep -iE 'barman|archive|wal-push|error' | tail -20
```

## Root-cause investigation

| Symptom | Cause |
|---|---|
| `barman-cloud-wal-archive` / `barman-cloud-backup` connection refused or timed out | the Pi backup store (versitygw on both Pis, the VIP :9000) down, or a NetworkPolicy dropping the egress |
| `AccessDenied`, `InvalidAccessKeyId` | the store credentials (the `<cluster>-backup-store` Secret, from Vault) wrong or rotated |
| `NoSuchBucket` | the `postgres-backups` bucket missing (tasks/versitygw.yml creates it) |
| `No space left` on the Pis | the Gluster backup volume full (`df -h /var/lib/minio/data` on a Pi) |
| an upgrade just moved the major | the old major's WAL archive cannot restore the new one: a fresh base backup is due (the upgrade's barman check takes it) |

## Fix

Fix the cause (above), then CNPG retries the pending segments by itself.

## Verification

The condition goes True; `kubectl -n $NS exec <primary> -c postgres -- psql -Atc 'select failed_count, last_failed_time, archived_count, last_archived_time from pg_stat_archiver'` shows `last_archived_time` moving.
