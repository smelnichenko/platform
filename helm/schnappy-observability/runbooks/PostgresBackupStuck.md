# PostgresBackupStuck

**Severity:** warning · **For:** 3h

## What fired

CloudNativePG has reported a backup running for 3 hours: the Cluster's `LastBackupSucceeded` condition is False with reason `BackupStarted` (`cnpg_cluster_condition{type="LastBackupSucceeded", reason="BackupStarted"} == 0`). Production's base backup takes minutes.

## How bad

CloudNativePG starts no backup while one is running, so no base backup is taken until this one ends. Each day without one lengthens the WAL replay of a restore. WAL archiving goes on (`PostgresArchivingFailed` says otherwise). `PostgresBackupMissed` fires a day later.

## First steps

```bash
NS=<namespace from the alert>; C=<cluster from the alert>
kubectl -n $NS get backups.postgresql.cnpg.io --sort-by=.metadata.creationTimestamp \
  -o custom-columns=NAME:.metadata.name,PHASE:.status.phase,STARTED:.status.startedAt,STOPPED:.status.stoppedAt | tail -5
kubectl -n $NS logs $(kubectl -n $NS get clusters.postgresql.cnpg.io $C -o jsonpath='{.status.currentPrimary}') -c postgres --since=4h \
  | grep -iE 'barman-cloud-backup|backup' | tail -20
```

## Root-cause investigation

| Symptom | Cause |
|---|---|
| the Backup `running`, the primary's log showing `barman-cloud-backup` ended (or no process running it) | its status lost: the API server or CloudNativePG's operator restarted while the backup ran (an upgrade's control-plane restart, 42-kubernetes-1.35, 2026-10-15) |
| `barman-cloud-backup` still running, the store slow | the Pi backup store (versitygw on both Pis, the VIP :9000) degraded, or the Gluster volume busy |
| the primary pod restarted during the backup | the backup's process gone with it; CloudNativePG did not notice |

## Fix

If the backup is still running in the primary, let it end. If it has ended or is gone, check what it left in the store (`barman-cloud-backup-list` against `s3://postgres-backups/<serverName>`, or the Pis' `/var/lib/minio/data`). Then delete the stuck Backup, `kubectl -n $NS delete backup <name>`, and take a new one: `kubectl -n $NS create -f - <<< "{apiVersion: postgresql.cnpg.io/v1, kind: Backup, metadata: {name: manual-$(date +%Y%m%d%H%M)}, spec: {cluster: {name: $C}}}"` (or the ops playbook postgres-base-backup.yml).

## Verification

The new Backup ends `completed`; the condition goes True; the alert resolves.
