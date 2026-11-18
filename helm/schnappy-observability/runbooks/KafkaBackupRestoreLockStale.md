# KafkaBackupRestoreLockStale

**Severity:** warning · **For:** 10m

## What fired

The ConfigMap `<namespace>-kafka-backup-restoring` - the lock ops' `tasks/kafka-restore.yml` makes for a restore's span
(the backup CronJob mounts it; its dump refuses while it is there) - was made more than 2 h ago
(`time() - kube_configmap_created{configmap=~".+-kafka-backup-restoring"} > 7200`). A restore's Job is bounded at an
hour. Either the run that made it died before its `always` step (its ssh dropped, the workstation slept, it was
stopped), or the restore failed after it began producing into Kafka - the run keeps the lock then, on purpose: a dump of
a Kafka half restored would be pruned in as the newest complete one. A restore that never touched Kafka (its Job never
made, its fetch failed) removes the lock itself.

## How bad

Every nightly Kafka dump refuses while the lock stays: KafkaBackupMissed follows after 26 h, the store keeps its older
dumps. The restore's own outcome is unknown until checked.

## First steps

The lock names the restore Job its run made (`job`) - judge that Job, never another restore's:

```bash
NS=schnappy-production LOCK=$NS-kafka-backup-restoring
kubectl -n $NS get configmap $LOCK -o jsonpath='{.data.since} {.data.job}{"\n"}'
J=<that job>
kubectl -n $NS get job $J -o jsonpath='{.status.active}/{.status.succeeded}/{.status.failed}{"\n"}'
kubectl -n $NS get pod -l job-name=$J -o jsonpath='{range .items[*].status.containerStatuses[?(@.name=="restore")]}{.state}{"\n"}{end}'
kubectl -n $NS logs job/$J -c fetch --tail=5; kubectl -n $NS logs job/$J -c restore --tail=20
```

## Fix

- **No such Job** (`NotFound`): the run died between the lock and the Job - Kafka untouched. Remove the lock
  (`kubectl -n $NS delete configmap $LOCK`) and run the restore again.
- **The Job active:** wait for it; the lock is its.
- **The Job succeeded** (`restored N messages from <dump>`, the line before it `topics <the topics restored>`): Kafka is
  restored; the run died before its BASELINE - without it the guard refuses every dump (the restored topics carry new
  TopicIds).
  1. the BASELINE for those topics (ops):
     `task deploy:kafka-backup-baseline -- -e kafka_baseline_topics='<the topics line>' -e kafka_baseline_why='a restore from <dump>'`
  2. the lock removed: `kubectl -n $NS delete configmap $LOCK`; the Job: `kubectl -n $NS delete job $J`
  3. a dump now (ops: `task check:production:kafka-backup`) - it must pass the guard; the restore's source stays pinned
     until Kafka is whole (ops: `task deploy:kafka-backup-unpin -- -e kafka_dump=<dump>`).
- **The Job failed, its `restore` container never started** (no state, or waiting: the `fetch` failed - a store blip,
  a dump damaged): Kafka untouched. Fix the cause, remove the lock and the Job, run the restore again.
- **The Job failed after `restore` started:** Kafka is partly restored. Remove the lock and the Job and run the restore
  again at once (`task deploy:kafka:restore -- -e kafka_dump=<the same dump> -e kafka_topics='...'`) - the guard refuses
  any dump in between (no BASELINE yet), so nothing half restored is kept. A topic the failed run cut off mid-produce
  holds some of the dump's messages and is refused: empty it first (delete its KafkaTopic and let Strimzi make it
  again), then restore.

## Why it exists

A dump of a Kafka half restored would be pruned in as the newest complete one, and the restore's own source could go.
