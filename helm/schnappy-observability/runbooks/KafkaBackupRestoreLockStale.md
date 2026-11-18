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

- A `kafka-restore-*` Job still active: wait for it; the lock is its.
- None active, the last one succeeded (`restored N messages from <dump>`): remove the lock, then take a dump now
  (ops: `tasks/kafka-backup.yml`):
  `kubectl -n $NS delete configmap $NS-kafka-backup-restoring`
- None active, the last one failed: Kafka is partly restored - the lock is kept on purpose (a dump now would capture
  the half). Finish the restore (ops' kafka-restore with that dump; it skips the topics already holding theirs), then
  remove the lock.

## Why it exists

A dump of a Kafka half restored would be pruned in as the newest complete one, and the restore's own source could go.
