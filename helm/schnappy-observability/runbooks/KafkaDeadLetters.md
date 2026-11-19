# KafkaDeadLetters

**Severity:** warning · **Fires:** for the 30 min after a dead letter

## What fired

An app's Kafka error handler (ops plan 127) gave up on records of `$labels.topic` and kept them on
`$labels.topic.DLT`. Each record got there one of two ways:

- **Retried, still failing.** The handler retried with its back-off: 1 s, doubling, at most 30 s apart, 15 min of waits
  in all. The record's partition waited the whole time. The store was down longer than that.
- **Not retryable.** No retry can fix the record: its value is not JSON (or names a type the app does not trust), or
  it is an event that names nothing (monitor: `InvalidUserEventException`, a user event with no type or no uuid).

The app counts each one as `kafka_dead_letters_total{topic}`. It also logs one line per record:
`Kafka record <topic>-<partition>@<offset> given up on, kept on <topic>.DLT`, with the failure's stack trace.

## Impact

The record is not in its store until it is replayed (monitor: the users table; chat: the message history). Nothing
was lost: the partition moved on, and the record waits on the DLT for its topic's retention (7 days). It is also in
the nightly Kafka backup.

## First steps

```bash
NS=schnappy-production
# the app's own line: which record, and why (monitor's container is "app")
kubectl -n $NS logs deploy/$NS-monitor -c app --since=2h | grep -A3 'given up on'
# the DLT: each record's headers (the failure: kafka_dlt-exception-fqcn, -cause-fqcn, -message; the original
# topic, partition, offset), its key and its value
kubectl -n $NS exec $NS-kafka-0 -c kafka -- /opt/kafka/bin/kafka-console-consumer.sh \
  --bootstrap-server localhost:9092 --topic user.events.DLT --from-beginning --timeout-ms 10000 \
  --formatter-property print.headers=true --formatter-property print.key=true --formatter-property print.offset=true
```

| `kafka_dlt-exception-cause-fqcn` | Cause | Then |
|---|---|---|
| `DataAccessResourceFailureException`, `CannotCreateTransactionException`, a driver's connection error | the store was down past the 15 min | bring the store back, then replay |
| `InvalidUserEventException` | the producer (admin) sent an event without a type or a uuid | fix the producer; replay nothing |
| `DeserializationException` | the value is not JSON, or its `__TypeId__` is not a trusted type | fix the producer; replay nothing |

## Replay

Fix the cause first. A record replayed into a store that is still down only comes back to the DLT.

Write the record back to its original topic with the header the app reads. Monitor and chat read Spring's
`__TypeId__`; take its value from the DLT record's headers. The console producer reads headers, key and value
separated by tabs:

```bash
printf '__TypeId__:java.util.HashMap\tUSER_CREATED\t%s\n' '<the value: its JSON, one line>' \
  | kubectl -n $NS exec -i $NS-kafka-0 -c kafka -- /opt/kafka/bin/kafka-console-producer.sh \
      --bootstrap-server localhost:9092 --topic user.events \
      --reader-property parse.headers=true --reader-property parse.key=true
```

A topic read by several apps shares one DLT. `user.events` is read by monitor (`user-sync`), chat (`chat-user`),
chess (`chess-user`) and masi (`masi-user`). The `kafka_dlt-original-consumer-group` header names the app that gave
up. A replay to the topic reaches every app's group, not only that one. Each of them stores a user event
idempotently (an upsert, a cache entry); only chat's admin-channel notices (`EMAIL_VERIFIED`, `REGISTRATION_*`) post a
second time.

Replaying twice is safe: monitor upserts the user, and chat writes a message under its own id.

The DLT keeps the record after a replay; it ages out with the topic's retention. Check that the record reached its
store (the user's row, the message in its channel). The alert stops 30 min after the last dead letter.
