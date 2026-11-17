set -eu
# ClickHouse's backups in the Pi store (STORE: rclone's remote and bucket): the newest KEEP complete ones kept - a
# complete one has its .backup file, ClickHouse's last write - every older complete one removed; an incomplete one
# (a backup failed or still running) removed once a day old. Only names as the backup job writes them. A listing that
# fails stops the prune before anything is removed: a store blip never makes a complete backup look incomplete.
rclone mkdir "$STORE"
rc=0
listing=$(rclone lsf --dirs-only "$STORE/logs/") || rc=$?
# 3: rclone's "directory not found" - no backup made yet
[ "$rc" -eq 0 ] || [ "$rc" -eq 3 ] || { echo "listing $STORE/logs/ failed (rclone rc=$rc): nothing removed"; exit 1; }
names=$(printf '%s\n' "$listing" | sed 's#/$##' | grep -E '^[0-9]{8}T[0-9]{6}Z$' | sort || true)
complete=""
for n in $names; do
  top=$(rclone lsf --files-only --max-depth 1 "$STORE/logs/$n/")
  if printf '%s\n' "$top" | grep -qx '.backup'; then complete="$complete $n"; fi
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
  echo "removing logs/$n (complete, older than the newest $KEEP)"
  rclone purge "$STORE/logs/$n"
  removed=$((removed + 1))
done
for n in $names; do
  case " $complete " in *" $n "*) continue ;; esac
  if [ "$(echo "$n" | tr -d TZ)" -lt "$cutoff" ]; then
    echo "removing logs/$n (incomplete, a day old)"
    rclone purge "$STORE/logs/$n"
    removed=$((removed + 1))
  else
    echo "keeping logs/$n (incomplete, less than a day old - a backup still running)"
  fi
done
echo "clickhouse backups: $total complete, $removed removed, the newest $KEEP complete kept"
