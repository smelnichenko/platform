set -eu
# Backups in the Pi store (STORE: rclone's remote and bucket; PREFIX: the folder holding them, "" or "<name>/"): the
# newest KEEP complete ones kept - a complete one holds MARKER, its writer's last file (ClickHouse's .backup, the Kafka
# dump's DONE) - every older complete one removed; an incomplete one (failed, or still being written) removed once a day
# old. Only names as the backup jobs write them (<UTC timestamp>Z). A listing that fails stops the prune before anything
# is removed: a store blip never makes a complete backup look incomplete. A backup holding PIN (default PINNED - a
# restore pins the dump it came from until the operator unpins it) is never removed, complete or not: the restore's
# source must outlive the nights after it. A backup's MARKER goes first, then the rest: a purge cut short leaves an
# incomplete backup, never a complete-looking one with files missing. One script for every chart's backups (platform
# CI: the copies equal).
PREFIX=${PREFIX-logs/}
MARKER=${MARKER:-.backup}
PIN=${PIN:-PINNED}
rclone mkdir "$STORE"
rc=0
listing=$(rclone lsf --dirs-only "$STORE/$PREFIX") || rc=$?
# 3: rclone's "directory not found" - no backup made yet
[ "$rc" -eq 0 ] || [ "$rc" -eq 3 ] || { echo "listing $STORE/$PREFIX failed (rclone rc=$rc): nothing removed"; exit 1; }
names=$(printf '%s\n' "$listing" | sed 's#/$##' | grep -E '^[0-9]{8}T[0-9]{6}Z$' | sort)
complete="" pinned=""
for n in $names; do
  top=$(rclone lsf --files-only --max-depth 1 "$STORE/$PREFIX$n/")
  if printf '%s\n' "$top" | grep -qxF "$MARKER"; then complete="$complete $n"; fi
  if printf '%s\n' "$top" | grep -qxF "$PIN"; then pinned="$pinned $n"; fi
done
total=$(echo $complete | wc -w)
drop=0
[ "$total" -le "$KEEP" ] || drop=$((total - KEEP))
cutoff=$(date -u -d "@$(($(date +%s) - 86400))" +%Y%m%d%H%M%S)
removed=0
i=0
for n in $complete; do
  i=$((i + 1))
  [ "$i" -le "$drop" ] || break
  case " $pinned " in *" $n "*) echo "keeping $PREFIX$n (complete, older than the newest $KEEP - pinned: a restore's source)"; continue ;; esac
  echo "removing $PREFIX$n (complete, older than the newest $KEEP)"
  rclone deletefile "$STORE/$PREFIX$n/$MARKER"
  rclone purge "$STORE/$PREFIX$n"
  removed=$((removed + 1))
done
for n in $names; do
  case " $complete " in *" $n "*) continue ;; esac
  case " $pinned " in *" $n "*) echo "keeping $PREFIX$n (incomplete - pinned)"; continue ;; esac
  if [ "$(echo "$n" | tr -d TZ)" -lt "$cutoff" ]; then
    echo "removing $PREFIX$n (incomplete, a day old)"
    rclone purge "$STORE/$PREFIX$n"
    removed=$((removed + 1))
  else
    echo "keeping $PREFIX$n (incomplete, less than a day old - a backup still running)"
  fi
done
echo "backups in $STORE/$PREFIX: $total complete, $removed removed, the newest $KEEP complete kept"
