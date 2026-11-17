#!/bin/sh
# A stub Kafka for kafka-backup-test.sh: writes its tools into $1/bin, over a world of files in $1/k -
#   k/<topic>/parts             its partition count
#   k/<topic>/<p>.log           its messages, one per line, as the dump writes them (headers TAB key TAB value)
#   k/<topic>/<p>.start         its earliest offset (0 when absent)
#   k/groups                    "<group> <topic> <partition> <offset>" lines
#   k/members/<group>           its member count (0 when absent)
# Knobs (environment): DROP_PART=<topic>:<p> leaves a partition out of get-offsets' answer (as Kafka's tool does for one it
# cannot list); SHORT=<n> makes a read <n> messages short; LOSE=1 makes the producer drop its last line (unacknowledged).
# Every call is logged to $1/calls.
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
      printf 'Topic: %s\tTopicId: x\tPartitionCount: %s\tReplicationFactor: 1\tConfigs:\n' "$b" "$(parts "$b")"
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
p=0; while [ "$p" -lt "$(parts "$t")" ]; do
  if [ "${DROP_PART:-}" != "$t:$p" ]; then
    s=$(start "$t" "$p"); if [ "$time" = -2 ]; then echo "$t:$p:$s"; else echo "$t:$p:$((s + $(lines "$t" "$p")))"; fi
  fi
  p=$((p + 1)); done
S
cat > "$W/bin/kafka-console-consumer.sh" << 'S'
#!/bin/sh
. "$W/bin/common.sh"; log "$@"
t=""; p=""; o=""; n=""
while [ $# -gt 0 ]; do case "$1" in --topic) t=$2; shift ;; --partition) p=$2; shift ;; --offset) o=$2; shift ;; --max-messages) n=$2; shift ;; esac; shift; done
from=$((o - $(start "$t" "$p") + 1))
sed -n "${from},\$p" "$K/$t/$p.log" | head -n $((n - ${SHORT:-0}))
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
chmod +x "$W/bin"/kafka-*.sh
