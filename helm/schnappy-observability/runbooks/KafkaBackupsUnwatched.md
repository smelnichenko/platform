# KafkaBackupsUnwatched

**Severity:** warning · **For:** 1h

## What fired

Kafka's backups are on (schnappy-data's `strimzi.backup.enabled`), but kube-state-metrics lists no
`<release>-kafka-backup` CronJob in the namespace (`absent(kube_cronjob_info{...})`). KafkaBackupMissed and
KafkaBackupNeverSucceeded read that CronJob: with it gone, both are silent.

## How bad

Nothing says whether Kafka's topics are backed up.

## First steps

```bash
kubectl -n schnappy-production get cronjobs | grep kafka
kubectl -n argocd get application schnappy-production-data -o jsonpath='{.status.sync.status} {.status.operationState.phase}{"\n"}'
```

## Root-cause investigation

| Symptom | Cause |
|---|---|
| no CronJob, the app OutOfSync | deleted by hand: Argo's selfHeal makes it again on its next sync |
| no CronJob, the app Synced | a values change renamed it (the release's name) - the alert names the old one |
| the CronJob there | kube-state-metrics not scraping CronJobs, or not scraped at all |

## Fix

Bring the CronJob back (an Argo sync), or fix the name.

## Verification

`kube_cronjob_info{cronjob=~".+-kafka-backup"}` has a series; the alert resolves.
