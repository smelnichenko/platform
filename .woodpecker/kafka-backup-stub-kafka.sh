#!/bin/sh
# A stub Kafka for kafka-backup-test.sh: writes its tools into $1/bin, over a world of files in $1/k -
#   k/<topic>/parts             its partition count
#   k/<topic>/<p>.log           its messages, one per line, as the dump writes them (headers TAB key TAB value)
#   k/<topic>/<p>.start         its earliest offset (0 when absent)
#   k/<topic>/id                its TopicId (x when absent)
#   k/<topic>/<p>.times         each message's timestamp (ms), a line each (absent: none at or after any time asked)
#   k/<topic>/retention         its retention.ms (604800000 - the broker's 168 h - when absent)
#   k/groups                    "<group> <topic> <partition> <offset>" lines
#   k/members/<group>           its member count (0 when absent)
# Knobs (environment): DROP_PART=<topic>:<p> leaves a partition out of get-offsets' answer (as Kafka's tool does for one it
# cannot list); SHORT=<n> makes a read <n> messages short; LOSE=1 makes the producer drop its last line (unacknowledged);
# START_SHIFT=<n> moves each log's start <n> on for the consumer alone (retention between the offsets read and the read);
# EXTRA_LINE=<text> adds a line that is no message after a read's first.
# MAKE_RESTORING=<file> makes a read create that file (a restore's ConfigMap appearing while the dump reads);
# NO_RETENTION=<topic> leaves a topic's retention.ms out of kafka-configs' answer.
# Every call is logged to $1/calls. The consumer's deprecated --consumer-property prints its notice on stdout, as Kafka
# 4.3.1's does.
set -eu
W=$1
mkdir -p "$W/bin" "$W/k/members"
cat > "$W/bin/common.sh" << 'C'
K="$W/k"
log() { echo "$(basename "$0") $*" >> "$W/calls"; }
parts() { cat "$K/$1/parts"; }
start() { cat "$K/$1/$2.start" 2> /dev/null || echo 0; }
lines() { [ -f "$K/$1/$2.log" ] && wc -l < "$K/$1/$2.log" | tr -d ' ' || echo 0; }
C
cat > "$W/bin/kafka-topics.sh" << 'S'
#!/bin/sh
. "$W/bin/common.sh"; log "$@"
t=""; mode=""
while [ $# -gt 0 ]; do case "$1" in --list) mode=list ;; --describe) mode=describe ;; --topic) t=$2; shift ;; esac; shift; done
case "$mode" in
  list) for d in "$K"/*/; do b=$(basename "$d"); [ "$b" = members ] || echo "$b"; done ;;
  describe)
    for d in "$K"/*/; do b=$(basename "$d"); [ "$b" = members ] && continue; [ -z "$t" ] || [ "$b" = "$t" ] || continue
      printf 'Topic: %s\tTopicId: %s\tPartitionCount: %s\tReplicationFactor: 1\tConfigs:\n' "$b" "$(cat "$K/$b/id" 2> /dev/null || echo x)" "$(parts "$b")"
      p=0; while [ "$p" -lt "$(parts "$b")" ]; do printf '\tTopic: %s\tPartition: %s\tLeader: 1\n' "$b" "$p"; p=$((p + 1)); done
    done
    [ -z "$t" ] || [ -d "$K/$t" ] || { echo "Error: topic $t not found" >&2; exit 1; } ;;
esac
S
cat > "$W/bin/kafka-get-offsets.sh" << 'S'
#!/bin/sh
. "$W/bin/common.sh"; log "$@"
t=""; time=""
while [ $# -gt 0 ]; do case "$1" in --topic) t=$2; shift ;; --time) time=$2; shift ;; esac; shift; done
# --topic '.*': every topic (the regex the dump's checkpoints ask with); else the one named
if [ "$t" = '.*' ]; then ts=$(for d in "$K"/*/; do b=$(basename "$d"); [ "$b" = members ] || echo "$b"; done); else ts=$t; fi
for t in $ts; do
p=0; while [ "$p" -lt "$(parts "$t")" ]; do
  if [ "${DROP_PART:-}" != "$t:$p" ]; then
    s=$(start "$t" "$p")
    case "$time" in
      -2) echo "$t:$p:$s" ;;
      -1) echo "$t:$p:$((s + $(lines "$t" "$p")))" ;;
      # the first message at or after the time; none - the partition left out, as Kafka's tool does
      *) [ ! -f "$K/$t/$p.times" ] || awk -v x="$time" -v s="$s" -v tp="$t:$p" '$1 + 0 >= x + 0 { print tp ":" s + NR - 1; exit }' "$K/$t/$p.times" ;;
    esac
  fi
  p=$((p + 1)); done
done
S
cat > "$W/bin/kafka-console-consumer.sh" << 'S'
#!/bin/sh
. "$W/bin/common.sh"; log "$@"
t=""; p=""; o=""; n=""; reset=""
# Kafka 4.3.1's notice for the deprecated spelling, on stdout before the messages (as measured); either spelling sets
# the reset policy
while [ $# -gt 0 ]; do case "$1" in --topic) t=$2; shift ;; --partition) p=$2; shift ;; --offset) o=$2; shift ;; --max-messages) n=$2; shift ;;
  --command-property) case "$2" in auto.offset.reset=*) reset=${2#auto.offset.reset=} ;; esac; shift ;;
  --consumer-property) echo "Option --consumer-property is deprecated and will be removed in a future version. Use --command-property instead."
    case "$2" in auto.offset.reset=*) reset=${2#auto.offset.reset=} ;; esac; shift ;;
  esac; shift; done
# an offset outside the log (START_SHIFT: retention moved its start since get-offsets read it), by the reset policy:
# none - an error (measured: OffsetOutOfRangeException); earliest - from the log's start, what is left; latest (the
# console consumer's default without --from-beginning) - the log's end, nothing read
lo=$(( $(start "$t" "$p") + ${START_SHIFT:-0} )); hi=$(( $(start "$t" "$p") + $(lines "$t" "$p") ))
if [ "$o" -lt "$lo" ] || [ "$o" -gt "$hi" ]; then
  case "$reset" in
    none) echo "org.apache.kafka.clients.consumer.OffsetOutOfRangeException: offset $o out of range for $t-$p" >&2; exit 1 ;;
    earliest) o=$lo ;;
    *) exit 0 ;;
  esac
fi
from=$((o - $(start "$t" "$p") + 1))
# EXTRA_LINE=<text>: a line after the first message that is none (a value's fragment, split at a raw newline)
# its closing line on stderr, as Kafka's: "Processed a total of <n> messages"
[ -z "${MAKE_RESTORING:-}" ] || echo 20261118T030000Z > "$MAKE_RESTORING"
r=$(mktemp)
sed -n "${from},\$p" "$K/$t/$p.log" | head -n $((n - ${SHORT:-0})) \
  | { if IFS= read -r l; then printf '%s\n' "$l"; [ -z "${EXTRA_LINE:-}" ] || printf '%s\n' "$EXTRA_LINE"; fi; cat; } > "$r"
cat "$r"; echo "Processed a total of $(wc -l < "$r" | tr -d ' ') messages" >&2; rm -f "$r"
S
cat > "$W/bin/kafka-console-producer.sh" << 'S'
#!/bin/sh
. "$W/bin/common.sh"; log "$@"
t=""; h=true
while [ $# -gt 0 ]; do case "$1" in --topic) t=$2; shift ;; --reader-property) case "$2" in parse.headers=*) h=${2#parse.headers=} ;; esac; shift ;; esac; shift; done
in=$(cat); [ "${LOSE:-}" = 1 ] && in=$(printf '%s\n' "$in" | sed '$d')
printf '%s\n' "$in" | while IFS= read -r l; do
  [ -n "$l" ] || continue
  [ "$h" = true ] || l=$(printf 'NO_HEADERS\t%s' "$l")
  key=$(printf '%s' "$l" | cut -f2)
  if [ "$key" = __NULL__ ]; then p=0; else p=$(( $(printf '%s' "$key" | cksum | cut -d' ' -f1) % $(parts "$t") )); fi
  printf '%s\n' "$l" >> "$K/$t/$p.log"
done
S
cat > "$W/bin/kafka-consumer-groups.sh" << 'S'
#!/bin/sh
. "$W/bin/common.sh"; log "$@"
g=""; mode=""
while [ $# -gt 0 ]; do case "$1" in --all-groups) mode=all ;; --group) g=$2; shift ;; --state) mode=state ;; --reset-offsets) mode=reset ;; esac; shift; done
case "$mode" in
  all) echo "GROUP TOPIC PARTITION CURRENT-OFFSET"; cat "$K/groups" 2> /dev/null || true ;;
  state) echo "GROUP COORDINATOR (ID) ASSIGNMENT-STRATEGY STATE #MEMBERS"; echo "$g b:9092 (1) range Empty $(cat "$K/members/$g" 2> /dev/null || echo 0)" ;;
esac
S
cat > "$W/bin/kafka-configs.sh" << 'S'
#!/bin/sh
. "$W/bin/common.sh"; log "$@"
for d in "$K"/*/; do b=$(basename "$d"); [ "$b" = members ] && continue
  echo "All configs for topic $b are:"
  echo "  cleanup.policy=delete sensitive=false synonyms={DEFAULT_CONFIG:log.cleanup.policy=delete}"
  # as Kafka 4.x prints them: local.retention.ms (tiered storage's, -2) before retention.ms - never read as it
  echo "  local.retention.ms=-2 sensitive=false synonyms={DEFAULT_CONFIG:log.local.retention.ms=-2}"
  if [ "${NO_RETENTION:-}" != "$b" ]; then
    if [ -f "$K/$b/retention" ]; then echo "  retention.ms=$(cat "$K/$b/retention") sensitive=false synonyms={DYNAMIC_TOPIC_CONFIG:retention.ms=$(cat "$K/$b/retention")}"
    else echo "  retention.ms=604800000 sensitive=false synonyms={DEFAULT_CONFIG:log.retention.hours=168}"; fi
  fi
  echo "  retention.bytes=-1 sensitive=false synonyms={DEFAULT_CONFIG:log.retention.bytes=-1}"
done
S
chmod +x "$W/bin"/kafka-*.sh
