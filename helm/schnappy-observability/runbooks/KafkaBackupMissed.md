# KafkaBackupMissed

**Severity:** warning · **For:** 1h

## What fired

The Kafka backup CronJob's last successful run ended more than 26 h ago
(`time() - kube_cronjob_status_last_successful_time{cronjob=~".+-kafka-backup"} > 26 * 3600`): the nightly dump of
Kafka's topics did not land in the Pi store (bucket `kafka-backups`).

## How bad

The topics' messages since the newest complete dump have no copy (the topics keep 7 days; the services' own data is
in Postgres and ScyllaDB). The prune never removes the newest complete dumps, so an older one is still there.

## First steps

```bash
NS=schnappy-production
kubectl -n $NS get cronjob schnappy-production-kafka-backup
kubectl -n $NS get jobs --sort-by=.metadata.creationTimestamp | grep kafka-backup | tail -4
kubectl -n $NS logs job/<the newest schnappy-production-kafka-backup-... job> -c dump --tail=30
kubectl -n $NS logs job/<the same job> -c upload --tail=30
```

## Root-cause investigation

| Symptom | Cause |
|---|---|
| `dump`: `<topic>[<p>]: N messages read, its offsets say M` | a message holding a newline (one line per message breaks), or a transactional/compacted topic (offsets with no message) - the dump refuses to pass short |
| `dump`: a timeout or connection reset to `...-kafka-bootstrap:9092` | Kafka down, or the job's pod without its native sidecar (Kafka's 9092 takes mTLS only: the pod's `sidecar.istio.io/nativeSidecar` annotation) |
| `dump`: `partitions '...', its N partitions are '...'` | a partition without a leader when the offsets were read - Kafka unhealthy |
| `dump`: `a carriage return` / `not valid UTF-8` / `fewer than three fields` | a message the line format cannot carry - a producer writing other than Spring's JSON |
| `upload`: connection refused / timeout to the store | the Pi store (versitygw, the VIP :9000) down, or the job's NetworkPolicy |
| `upload`: `AccessDenied` | the store keys (`schnappy-production-kafka-backup-store`, from Vault's backup-store) wrong or rotated |
| no job at all | the CronJob suspended, or missed its start by more than an hour |

## Fix

Fix the cause, then take a dump now:

```bash
kubectl -n schnappy-production create job --from=cronjob/schnappy-production-kafka-backup kafka-backup-manual-$(date +%s)
```

## Verification

Both containers end 0, the upload's log names the dump; the CronJob's last successful time is recent and the alert
resolves within an hour.

## Turning backups off

`strimzi.backup.enabled: false` - but the data ApplicationSet has no prune: the CronJob, its ConfigMap, ExternalSecret
and NetworkPolicy stay and the CronJob keeps running. Delete them (the operator's OK for each, on ten):

```bash
kubectl -n schnappy-production delete cronjob schnappy-production-kafka-backup
kubectl -n schnappy-production delete configmap schnappy-production-kafka-backup
kubectl -n schnappy-production delete externalsecret schnappy-production-kafka-backup-store
kubectl -n schnappy-production delete secret schnappy-production-kafka-backup-store --ignore-not-found
kubectl -n schnappy-production delete networkpolicy schnappy-production-kafka-backup
```
