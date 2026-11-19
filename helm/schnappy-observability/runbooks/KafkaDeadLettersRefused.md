# KafkaDeadLettersRefused

**Severity:** critical · **Fires:** at once

## What fired

`$labels.job` gave up on a record of `$labels.topic`, and `$labels.topic.DLT` refused it. The record was not committed,
and the error handler retries it again from the start, holding the listener: every partition that consumer reads
waits behind it. It counts each refusal as `kafka_dead_letters_refused_total{topic}`.

## First steps

```bash
NS=schnappy-production
# the topic: does it exist, with its partitions?
kubectl -n $NS exec $NS-kafka-0 -c kafka -- /opt/kafka/bin/kafka-topics.sh --bootstrap-server localhost:9092 \
  --describe --topic user.events.DLT
kubectl -n $NS get kafkatopics | grep -i dlt
# the producer's error, in the app's log
kubectl -n $NS logs deploy/$NS-monitor -c app --since=30m | grep -i -E 'dead-letter|DLT|TopicAuthorization|UnknownTopic' | tail -20
```

| cause | fix |
|---|---|
| no such topic (auto-create off, its KafkaTopic gone) | restore the DLT's KafkaTopic (platform's schnappy-data `kafka.topics`) |
| `TopicAuthorizationException` | the app's KafkaUser lacks Write on the DLT (`kafka-users.yaml`), if SCRAM authorization is on |
| a timeout | the broker is away: see KafkaBrokerDown |

Once the DLT takes records, the held record goes there on its next try, `KafkaDeadLetters` fires for it, and the
listener goes on.
