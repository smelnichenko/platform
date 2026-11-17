# ClickHouseBackupMissed

**Severity:** warning · **For:** 1h

## What fired

The ClickHouse backup CronJob's last successful run ended more than 26 h ago
(`time() - kube_cronjob_status_last_successful_time{cronjob=~".+-clickhouse-backup"} > 26 * 3600`): the nightly
`BACKUP DATABASE logs` did not land in the Pi store.

## How bad

The logs since the newest complete backup have no copy. The prune never removes the last complete backups (it keeps
the newest 7 complete ones whatever happens), so an older restore point is still there.

## First steps

```bash
NS=schnappy-infra
kubectl -n $NS get cronjob schnappy-clickhouse-backup schnappy-clickhouse-backup-prune
kubectl -n $NS get jobs --sort-by=.metadata.creationTimestamp | grep clickhouse-backup | tail -6
kubectl -n $NS logs job/<the newest schnappy-clickhouse-backup-... job> -c backup
kubectl -n $NS logs schnappy-clickhouse-0 -c clickhouse --since=26h | grep -iE 'backup|s3|named collection' | tail -20
```

## Root-cause investigation

| Symptom | Cause |
|---|---|
| `Connection refused` / timeout to the store in ClickHouse's log | the Pi store (versitygw on both Pis, the VIP :9000) down, or ClickHouse's NetworkPolicy without the store's egress |
| `Access Denied` / `InvalidAccessKeyId` | the store keys (`schnappy-clickhouse-backup-store`, from Vault's backup-store) wrong or rotated - ClickHouse reads them at start: restart it after a rotation |
| `NoSuchBucket` | `clickhouse-backups` missing - the prune job makes it; run it (`kubectl create job --from=cronjob/schnappy-clickhouse-backup-prune ...`) |
| `There is no named collection backup_store` | ClickHouse started without `config.d/50-backup.xml` (the chart's `clickhouse.backup.enabled`) |
| the client cannot connect (`Connection refused` to schnappy-clickhouse:9000) | ClickHouse down, or the job's sidecar not ready - the job retries once |
| no job created at all | the CronJob suspended, or missed its start by more than an hour (`startingDeadlineSeconds`) |

## Fix

Fix the cause, then take a backup now:

```bash
kubectl -n schnappy-infra create job --from=cronjob/schnappy-clickhouse-backup clickhouse-backup-manual-$(date +%s)
```

## Verification

The job completes with `BACKUP_CREATED`; the CronJob's last successful time is recent and the alert resolves within
an hour.
