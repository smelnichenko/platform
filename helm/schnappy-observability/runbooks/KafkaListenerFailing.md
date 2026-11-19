# KafkaListenerFailing

**Severity:** warning · **For:** 10 min

## What fired

`$labels.job`'s Kafka listener `$labels.name` has failed on every try for 10 min, with no success between. Its error
handler (ops plan 127) is holding it on one record. The handler blocks: that consumer's thread waits, and every
partition it reads waits with it. Nothing is lost; the records wait in Kafka.

The two ways a listener gets held:

- **its store is away** (Postgres restarting, its connections refused, the database starting up). The handler waits
  for the store however long it is away, 1 s doubling to 30 s between tries, and never gives up on the record. This
  is the expected case during a store restart, and it clears when the store is back.
- **any other failure**, on its way to the DLT: retried for 15 min, then the record goes to `<topic>.DLT` (and
  `KafkaDeadLetters` fires).

## First steps

```bash
NS=schnappy-production
# the failures (Spring logs each try at ERROR: "Seek to current after exception"), and their cause
kubectl -n $NS logs deploy/$NS-monitor -c app --since=30m | grep -B2 -A12 'Seek to current after exception' | tail -60
# is the store up?
kubectl -n $NS get clusters.postgresql.cnpg.io
```

## What to do

- **The store is away:** bring it back. The listener goes on by itself with the record it held, in order.
- **The store is up and the failure is something else:** that record goes to the DLT after its 15 min. Read the cause
  in the log now; see the KafkaDeadLetters runbook for what follows.
- **It does not clear after the store is back:** the cause is not the store. Read the exception, and restart nothing
  until you know it. A restart keeps the record (its offset is not committed), and the next pod holds on it again.
