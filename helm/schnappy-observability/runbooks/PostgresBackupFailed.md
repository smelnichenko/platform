# PostgresBackupFailed

**Severity:** critical · **For:** 5m

## What fired

CloudNativePG reports the Cluster's `LastBackupSucceeded` condition False: its last base backup failed (`cnpg_cluster_condition{type="LastBackupSucceeded"} == 0`).

## How bad

The newest restorable base backup is older than intended; with WAL archiving also failing (`PostgresArchivingFailed`) no recent restore point exists.

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

Fix the cause, then take a backup: `kubectl -n $NS create -f - <<< "{apiVersion: postgresql.cnpg.io/v1, kind: Backup, metadata: {name: manual-$(date +%Y%m%d%H%M)}, spec: {cluster: {name: $C}}}"` (or the ops playbook postgres-base-backup.yml).

## Verification

The new Backup ends `completed`; the condition goes True.
