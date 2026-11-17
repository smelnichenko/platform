# KafkaBackupNeverSucceeded

**Severity:** warning · **For:** 26h

## What fired

The Kafka backup CronJob exists but kube-state-metrics has no last successful time for it
(`kube_cronjob_info{cronjob=~".+-kafka-backup"} unless kube_cronjob_status_last_successful_time`): since it was created a
day ago, no run has completed.

## How bad

Kafka's topics have no dump at all.

## First steps

As in [KafkaBackupMissed](KafkaBackupMissed.md): the newest job's `dump` and `upload` logs, Kafka, the store. A first
night commonly fails on the store's egress (the job's NetworkPolicy) or the store's keys.

## Fix

Fix the cause and take a dump now:

```bash
kubectl -n schnappy-production create job --from=cronjob/schnappy-production-kafka-backup kafka-backup-manual-$(date +%s)
```

## Verification

The job completes; the alert resolves.
