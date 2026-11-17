# ClickHouseBackupNeverSucceeded

**Severity:** warning · **For:** 26h

## What fired

The ClickHouse backup CronJob exists but kube-state-metrics has no last successful time for it
(`kube_cronjob_info{cronjob=~".+-clickhouse-backup"} unless kube_cronjob_status_last_successful_time`): since it was
created a day ago, no run has completed.

## How bad

ClickHouse's logs have no backup at all.

## First steps

The same as [ClickHouseBackupMissed](ClickHouseBackupMissed.md): the newest job's log, ClickHouse's log, the store.
A first night commonly fails on the store's egress (ClickHouse's NetworkPolicy) or a missing bucket (the prune job
makes it - it runs before the backup).

## Fix

Fix the cause and take a backup now:

```bash
kubectl -n schnappy-infra create job --from=cronjob/schnappy-clickhouse-backup clickhouse-backup-manual-$(date +%s)
```

## Verification

The job completes with `BACKUP_CREATED`; the alert resolves.
