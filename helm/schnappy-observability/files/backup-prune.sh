set -eu
# Backups in the Pi store (STORE: rclone's remote and bucket; PREFIX: the folder holding them, "" or "<name>/"): the
# newest KEEP complete ones kept - a complete one holds MARKER, its writer's last file (ClickHouse's .backup, the Kafka
# dump's DONE) - every older complete one removed; an incomplete one (failed, or still being written) removed once a day
# old. Only names as the backup jobs write them (<UTC timestamp>Z). A listing that fails stops the prune before anything
# is removed: a store blip never makes a complete backup look incomplete. With NONEMPTY=<field> a complete backup's MARKER
# holds a count at that whitespace field of its first line (the Kafka dump's DONE: "<ts> <n> topics <m> messages", 4):
# the newest complete one counting more than 0 is never removed, however many newer ones count 0 - a Kafka that lost
# its messages but not its topics (the topic operator makes them again) dumps nothing night after night, and the prune
# would otherwise take every good dump within KEEP days. A MARKER without that count stops the prune. One script for
# every chart's backups (platform CI: the copies equal).
PREFIX=${PREFIX-logs/}
MARKER=${MARKER:-.backup}
rclone mkdir "$STORE"
rc=0
listing=$(rclone lsf --dirs-only "$STORE/$PREFIX") || rc=$?
# 3: rclone's "directory not found" - no backup made yet
[ "$rc" -eq 0 ] || [ "$rc" -eq 3 ] || { echo "listing $STORE/$PREFIX failed (rclone rc=$rc): nothing removed"; exit 1; }
names=$(printf '%s\n' "$listing" | sed 's#/$##' | grep -E '^[0-9]{8}T[0-9]{6}Z$' | sort || true)
complete=""
for n in $names; do
  top=$(rclone lsf --files-only --max-depth 1 "$STORE/$PREFIX$n/")
  if printf '%s\n' "$top" | grep -qxF "$MARKER"; then complete="$complete $n"; fi
done
total=$(echo $complete | wc -w)
held=""
if [ -n "${NONEMPTY:-}" ]; then
  for n in $complete; do  # oldest first: the last one counting more than 0 is the newest such
    m=$(rclone cat "$STORE/$PREFIX$n/$MARKER") || { echo "reading $PREFIX$n/$MARKER failed: nothing removed"; exit 1; }
    c=$(printf '%s\n' "$m" | awk -v f="$NONEMPTY" 'NR == 1 { print $f }')
    case "$c" in ''|*[!0-9]*) echo "$PREFIX$n/$MARKER holds no count at field $NONEMPTY ('$c'): nothing removed"; exit 1 ;; esac
    [ "$c" -eq 0 ] || held=$n
  done
fi
drop=0
[ "$total" -le "$KEEP" ] || drop=$((total - KEEP))
cutoff=$(date -u -d "@$(($(date +%s) - 86400))" +%Y%m%d%H%M%S)
removed=0
i=0
for n in $complete; do
  i=$((i + 1))
  [ "$i" -le "$drop" ] || break
  if [ "$n" = "$held" ]; then
    echo "keeping $PREFIX$n (complete, older than the newest $KEEP - but the newest holding anything: the newer ones count 0)"
    continue
  fi
  echo "removing $PREFIX$n (complete, older than the newest $KEEP)"
  rclone purge "$STORE/$PREFIX$n"
  removed=$((removed + 1))
done
for n in $names; do
  case " $complete " in *" $n "*) continue ;; esac
  if [ "$(echo "$n" | tr -d TZ)" -lt "$cutoff" ]; then
    echo "removing $PREFIX$n (incomplete, a day old)"
    rclone purge "$STORE/$PREFIX$n"
    removed=$((removed + 1))
  else
    echo "keeping $PREFIX$n (incomplete, less than a day old - a backup still running)"
  fi
done
echo "backups in $STORE/$PREFIX: $total complete, $removed removed, the newest $KEEP complete kept"
