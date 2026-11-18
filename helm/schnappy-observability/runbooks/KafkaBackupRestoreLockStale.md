# KafkaBackupRestoreLockStale

**Severity:** warning · **For:** 10m

## What fired

The ConfigMap `<namespace>-kafka-backup-restoring` - the lock ops' `tasks/kafka-restore.yml` makes for a restore's span
(the backup CronJob mounts it; its dump refuses while it is there) - was made more than 2 h ago
(`time() - kube_configmap_created{configmap=~".+-kafka-backup-restoring"} > 7200`). A restore's Job is bounded at an
hour: the run that made it died before its `always` step (its ssh dropped, the workstation slept, it was stopped).

## How bad

Every nightly Kafka dump refuses while the lock stays: KafkaBackupMissed follows after 26 h, the store keeps its older
dumps. The restore's own outcome is unknown until checked.

## First steps

```bash
NS=schnappy-production
kubectl -n $NS get configmap $NS-kafka-backup-restoring -o jsonpath='{.data.since}{"\n"}'
kubectl -n $NS get jobs | grep kafka-restore-        # a restore Job still running, or its last one's outcome
kubectl -n $NS logs job/<that kafka-restore-... job> -c restore --tail=20
```

## Fix

The run died before its last steps: the store's BASELINE (written after a restore succeeds) may not be there - the
backup's guard then refuses every dump (the restored topics carry new TopicIds).

- A `kafka-restore-*` Job still active: wait for it; the lock is its.
- None active, the last one succeeded (`restored N messages from <dump>`):
  1. the BASELINE for what it restored (ops):
     `task deploy:kafka-backup-baseline -- -e kafka_baseline_topics='<the restored topics>' -e kafka_baseline_why='restore from <dump>'`
  2. the lock removed: `kubectl -n $NS delete configmap $NS-kafka-backup-restoring`
  3. a dump now (ops: `task check:production:kafka-backup`) - it must pass the guard.
- None active, the last one failed: Kafka is partly restored. Remove the lock and run the restore again at once
  (`task deploy:kafka:restore -- -e kafka_dump=<the same dump> -e kafka_topics='...'`) - the guard refuses any dump in
  between (no BASELINE yet), so nothing half restored is kept. A topic the failed run cut off mid-produce holds some of
  the dump's messages and is refused: empty it first (delete its KafkaTopic and let Strimzi make it again), then restore.

## Why it exists

A dump of a Kafka half restored would be pruned in as the newest complete one, and the restore's own source could go.
