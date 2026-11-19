# UserEventOutboxStuck

**Severity:** warning · **For:** 5 min

## What fired

Admin's user events are not going out to Kafka: the oldest unsent one is older than 5 minutes, or the publisher's
heartbeat (`admin_user_events_outbox_turn_seconds`, each turn's end) is older than 2 minutes or gone. A user event (a user created, enabled or
disabled, a registration decided) is written to admin's `user_event_outbox` table in the transaction of the change it
announces; `UserEventOutboxPublisher` sends the unsent rows to `user.events` every second, in order, and marks each
sent. It stops at the first send that fails, so every event after it waits: monitor, chat, chess and masi are not told
until it goes. Nothing is lost - the rows stay in the table.

`admin_user_events_outbox_oldest_seconds` is the oldest unsent event's age, `admin_user_events_outbox_pending` how
many there are.

## First steps

```bash
NS=schnappy-production
# the publisher's own line for each failed try: the event, its try, the error
kubectl -n $NS logs deploy/$NS-admin --since=30m | grep 'not sent' | tail -5
# is Kafka up?
kubectl -n $NS get pods | grep kafka
# the rows waiting (read only), the first one is what holds the others
kubectl -n $NS exec $NS-postgres-1 -c postgres -- psql -U postgres -d admin -c \
  "SELECT id, event_type, event_key, attempts, last_error, created_at FROM user_event_outbox WHERE sent_at IS NULL ORDER BY id LIMIT 5"
```

## What to do

- **Kafka is away** (a timeout, `NotLeaderOrFollower`, a broker restarting): bring it back. The publisher sends the
  waiting events in order on its next turn by itself.
- **Kafka is up and the first row fails every time**: read its `last_error`. A row no send can take (it cannot be
  serialized, the topic refuses it) holds every event behind it. Fix the cause in admin; do not delete the row - the
  events behind it would go out, but the change it announces would never reach the other apps. If the row truly must
  go, set its `sent_at` (a decision: that event is then never sent), and make admin send the user's current state
  again.
- **The publisher does not run** (the heartbeat old or gone, no "not sent" lines): its thread (`user-event-outbox`) is
  stuck or never started. Read admin's log for "outbox turn failed" and JDBC errors; a thread dump
  (`kubectl exec ... -- jcmd 1 Thread.print`) shows where `user-event-outbox` waits. A restart of admin starts a fresh
  publisher; the unsent rows stay and go out in order.

## Before rolling admin back

Drain first: wait for `admin_user_events_outbox_pending` to read 0. An admin image from before the outbox sends events
directly and never reads the table; rows left unsent would go out only when the outbox comes back - after newer events,
a stale state over a fresh one.

The alert clears when the oldest unsent event is younger than 5 minutes.
