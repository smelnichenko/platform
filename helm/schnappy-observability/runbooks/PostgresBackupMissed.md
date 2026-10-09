# PostgresBackupMissed

**Severity:** warning · **For:** 1h

## What fired

The Cluster's last successful base backup ended more than 26 h ago (`time() - cnpg_cluster_last_successful_backup_timestamp_seconds > 26 * 3600`): the daily ScheduledBackup did not produce one.

## How bad

Restores need more WAL replayed (slower), and a WAL gap would leave only the old base backup.

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

Check the ScheduledBackup (`kubectl -n $NS get scheduledbackups.postgresql.cnpg.io`: suspended? its last schedule time?), fix, and take a backup as in [PostgresBackupFailed](PostgresBackupFailed.md).

## Verification

`.status.lastSuccessfulBackup` is recent; the alert resolves within an hour.
