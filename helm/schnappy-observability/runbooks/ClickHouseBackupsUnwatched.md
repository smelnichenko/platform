# ClickHouseBackupsUnwatched

**Severity:** warning · **For:** 1h

## What fired

ClickHouse's backups are on (the chart's `clickhouse.backup.enabled`), but kube-state-metrics lists no
`*-clickhouse-backup` CronJob (`absent(kube_cronjob_info{cronjob=~".+-clickhouse-backup"})`). ClickHouseBackupMissed and
ClickHouseBackupNeverSucceeded read that CronJob: with it gone, both are silent.

## How bad

Nothing says whether ClickHouse's logs are backed up.

## First steps

```bash
kubectl -n schnappy-infra get cronjobs | grep clickhouse
kubectl -n argocd get application schnappy-observability -o jsonpath='{.status.sync.status} {.status.operationState.phase}{"\n"}'
```

## Root-cause investigation

| Symptom | Cause |
|---|---|
| no CronJob, the app OutOfSync | deleted by hand: Argo's selfHeal makes it again on its next sync |
| no CronJob, the app Synced | a values change renamed it (the chart's fullname) - the alerts' regex no longer matches |
| the CronJob there | kube-state-metrics not scraping CronJobs (its collectors), or not scraped at all |

## Fix

Bring the CronJob back (an Argo sync), or fix the name the alerts match.

## Verification

`kube_cronjob_info{cronjob=~".+-clickhouse-backup"}` has a series; the alert resolves.
