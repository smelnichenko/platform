# KafkaDeadLetters

**Severity:** warning · **Fires:** for the 30 min after a dead letter

## What fired

An app's Kafka error handler gave up on records of `$labels.topic` and kept them on
`$labels.topic.DLT`. A dead letter is a record that no wait can fix:

- its value is not JSON, or names a type the app does not trust (`DeserializationException`);
- it names nothing: a user event with no type or no uuid (monitor: `InvalidUserEventException`);
- it breaks a constraint (`DataIntegrityViolationException`), for example a `USER_CREATED` under a new uuid for an email
  another user already has;
- any other failure that 15 min of retries did not fix: an app bug.

A store that is away (Postgres restarting, its connections refused) never dead-letters a record. The app waits for the
store however long it is away, holding its listener, and `KafkaListenerFailing` is the alert for that.

The app counts each dead letter as `kafka_dead_letters_total{topic}`. It also logs one line per record:
`Kafka record <topic>-<partition>@<offset> given up on, kept on <topic>.DLT`, with the failure's stack trace.

## Impact

The record's change is not in that app's store (monitor: the users table; chat: the message history). The
partition moved on. The record waits on the DLT for 7 days (its KafkaTopic's retention), and the nightly Kafka backup
keeps it too.

## First steps

```bash
NS=schnappy-production
# the app's own line: which record, and the stack trace (monitor's container is "app")
kubectl -n $NS logs deploy/$NS-monitor -c app --since=2h | grep -A5 'given up on'
# the DLT's records with their headers, keys and values
kubectl -n $NS exec $NS-kafka-0 -c kafka -- /opt/kafka/bin/kafka-console-consumer.sh \
  --bootstrap-server localhost:9092 --topic user.events.DLT --from-beginning --timeout-ms 10000 \
  --formatter-property print.headers=true --formatter-property print.key=true --formatter-property print.offset=true
```

Every DLT header is one line of text. The nightly backup dumps topics as text lines and refuses anything else.

| header | what it says |
|---|---|
| `kafka_dlt-original-topic`, `kafka_dlt-original-consumer-group` | where the record came from, and which app gave up on it |
| `dlt-original-partition`, `dlt-original-offset`, `dlt-original-timestamp` | the record's place and time, in text |
| `kafka_dlt-exception-fqcn`, `kafka_dlt-exception-cause-fqcn` | the failure's class, and its cause's |
| `dlt-exception-message` | the failure's message, on one line |
| `__TypeId__`, `__ContentTypeId__`, `__KeyTypeId__` | the original's type headers, copied |

| cause | what to do |
|---|---|
| `DeserializationException` | the producer sent something that is not the app's JSON. Fix the producer; replay nothing. |
| `InvalidUserEventException` | admin sent a user event with no type or no uuid. Fix admin; replay nothing. |
| `DataIntegrityViolationException` | the data conflicts, e.g. another row holds that email. Fix the data in the app's database (the old row), then have the source send the current state again. |
| anything else | an app bug. Fix it, deploy it, then decide about a replay (below). |

## Replay: rarely, and never an old state over a newer one

A record on the DLT is out of order: the events after it were applied. A user event carries a state (its email,
`enabled`). Replaying an old `USER_CREATED`, `USER_ENABLED` or `USER_DISABLED` overwrites whatever newer event has
since arrived for that user, in every app.

- **The topic is shared, and so is the DLT.** `user.events` is read by monitor (`user-sync`), chat (`chat-user`),
  chess (`chess-user`) and masi (`masi-user`); `kafka_dlt-original-consumer-group` names the one that gave up. A replay
  to the topic reaches every group, not only that one.
- **Prefer the source.** Make admin send the user's current state again, rather than re-sending the old record.
- **Replay a record only when** nothing newer exists for that key (no later event for that uuid on the topic), and the
  cause is fixed.

When a replay is right, it needs all three of the original's type headers. Spring's JsonDeserializer refuses a map
without `__ContentTypeId__` and `__KeyTypeId__`. Take them from the DLT record.

It also needs the original's key: the DLT record keeps it (`print.key=true` above). Admin keys a user event by the
user's uuid (a registration by its email), so a user's events are on one partition, in order. A replay under any other
key lands on another partition and can overtake, or be overtaken by, that user's live events:

```bash
printf '__TypeId__:java.util.HashMap,__ContentTypeId__:java.lang.Object,__KeyTypeId__:java.lang.Object\t%s\t%s\n' \
    '<the key, as the DLT record shows it: the user uuid>' '<the value: its JSON, one line>' \
  | kubectl -n $NS exec -i $NS-kafka-0 -c kafka -- /opt/kafka/bin/kafka-console-producer.sh \
      --bootstrap-server localhost:9092 --topic user.events \
      --reader-property parse.headers=true --reader-property parse.key=true
```

A chat message replayed once others followed it is appended as a second row after the chain's head - the chain stays
whole, the history shows it twice. One still at the head is not written again.

## Never delete the DLT or its records

The backup's guard compares each topic with the last dump. If a topic or its records disappear, it treats that as lost
data and refuses every backup after. Let records age out. If a DLT must go, run the baseline task for it afterwards:

```bash
task deploy:kafka-backup-baseline -- -e kafka_baseline_topics="user.events.DLT" -e kafka_baseline_why="<why>"
```

The alert stops 30 min after the last dead letter, whether or not anyone dealt with the record. Check the DLT before
calling it done.
