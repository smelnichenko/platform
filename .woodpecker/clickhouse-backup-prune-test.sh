#!/bin/sh
# ClickHouse's backup prune (files/clickhouse-backup-prune.sh, the CronJob's script) against a stub rclone over a store
# made of directories: the newest KEEP complete backups kept (complete = its .backup file), older complete ones and a
# day-old incomplete one removed, a fresh incomplete one kept, names not the job's never touched; a listing that fails
# removes nothing. And the CronJob renders that script.
set -eu
script=helm/schnappy-observability/files/clickhouse-backup-prune.sh
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
mkdir -p "$W/bin"
# the stub: store:<bucket>/<path> is $W/store/<bucket>/<path>; FAIL_LSF=<substring> fails a listing of a path holding it
cat > "$W/bin/rclone" << 'STUB'
#!/bin/sh
p() { echo "$W/store/${1#store:}"; }
echo "rclone $*" >> "$W/calls"
case "$1" in
  mkdir) mkdir -p "$(p "$2")" ;;
  purge) rm -rf "$(p "$2")" ;;
  lsf)
    path=$(eval echo "\${$#}")
    if [ -n "${FAIL_LSF:-}" ]; then case "$path" in *"$FAIL_LSF"*) echo "stub: listing $path failed" >&2; exit 1 ;; esac; fi
    d=$(p "$path")
    [ -d "$d" ] || exit 0
    case "$*" in
      *--dirs-only*) for e in "$d"/*/; do [ -d "$e" ] && basename "$e" | sed 's#$#/#'; done ;;
      *--files-only*) for e in "$d"/* "$d"/.[!.]*; do [ -f "$e" ] && basename "$e"; done ;;
    esac ;;
esac
exit 0
STUB
chmod +x "$W/bin/rclone"
fails=0
check() { if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1: got '$2', want '$3'"; fails=$((fails + 1)); fi; }
ts() { date -u -d "@$(($(date +%s) - $1 * 3600))" +%Y%m%dT%H%M%SZ; }
backup() { mkdir -p "$W/store/b/logs/$1/data"; [ "$2" = complete ] && : > "$W/store/b/logs/$1/.backup"; return 0; }
fresh() { rm -rf "$W/store" "$W/calls"; mkdir -p "$W/store"; }
run() { if W="$W" PATH="$W/bin:$PATH" STORE=store:b KEEP=${KEEP:-7} FAIL_LSF=${FAIL_LSF:-} sh "$script" > "$W/out" 2>&1; then echo rc=0; else echo "rc=$?"; fi; }
# each name fixed once (a name made again a second later is another name)
for h in 1 48 72 96 120 144 168 192 216; do eval "t$h=$(ts $h)"; done
left() { ls "$W/store/b/logs" 2> /dev/null | tr '\n' ' ' | sed 's/ $//'; }

# nine complete (oldest 9 days), one incomplete two days old, one incomplete an hour old, one not the job's name
fresh
for h in 216 192 168 144 120 96 72 48 24; do eval "n=\${t$h:-$(ts $h)}"; backup "$n" complete; done
backup "$(ts 49)" incomplete
new=$t1; backup "$new" incomplete
mkdir -p "$W/store/b/logs/manual-copy" "$W/store/b/logs/20200101T000000"
r=$(run)
check "nine complete, keep 7: the two oldest complete removed, the day-old incomplete removed, the fresh one and a foreign name kept" \
  "$r $(ls "$W/store/b/logs" | grep -c 'Z$') $(test -d "$W/store/b/logs/$t216" && echo old-kept || echo old-gone)$(test -d "$W/store/b/logs/$t192" && echo ' 2nd-kept' || echo ' 2nd-gone') $(test -d "$W/store/b/logs/$new" && echo fresh-kept) $(test -d "$W/store/b/logs/manual-copy" && test -d "$W/store/b/logs/20200101T000000" && echo foreign-kept)" \
  "rc=0 8 old-gone 2nd-gone fresh-kept foreign-kept"
check "  the newest seven complete all there" "$(for e in "$W"/store/b/logs/*/.backup; do echo x; done | wc -l | tr -d ' ')" 7

# every backup since failed: one complete five days old, newer incomplete ones - the complete one is never removed
fresh
backup "$t120" complete
for h in 96 72 48; do eval "backup \"\$t$h\" incomplete"; done
r=$(run)
check "only one complete backup (later ones failed): kept; the failed ones a day old removed" "$r $(left | wc -w | tr -d ' ') $(test -f "$W/store/b/logs/$t120/.backup" && echo kept)" "rc=0 1 kept"

# fewer than KEEP: nothing removed
fresh
for h in 72 48 1; do eval "backup \"\$t$h\" complete"; done
check "three complete, keep 7: nothing removed" "$(run) $(grep -c purge "$W/calls" || true)" "rc=0 0"

# the first night: no logs/ yet - the bucket made, nothing else
fresh
check "the first night: the bucket made, nothing removed" "$(run) $(grep -c '^rclone mkdir store:b$' "$W/calls") $(grep -c purge "$W/calls" || true)" "rc=0 1 0"

# a listing failing: nothing removed, red
fresh
for h in 216 192 168 144 120 96 72 48 1; do eval "backup \"\$t$h\" complete"; done
check "the store's listing failing: red, nothing removed" "$(FAIL_LSF=logs/ run) $(grep -c purge "$W/calls" || true)" "rc=1 0"
# one backup's own listing failing (it would look incomplete): red, nothing removed
check "one backup's listing failing: red, nothing removed - a complete one never taken for incomplete" \
  "$(FAIL_LSF="$t192" run) $(grep -c purge "$W/calls" || true)" "rc=1 0"

# the CronJob runs this script, as the chart renders it
out=$(helm template t helm/schnappy-observability/ --namespace schnappy-infra --set clickhouse.enabled=true --set clickhouse.existingSecret=ch \
  --set vault.secretsEnabled=true --set clickhouse.backup.enabled=true --set clickhouse.backup.endpoint=http://192.168.11.5:9000 \
  --set 'clickhouse.backup.storeIps={192.168.11.4,192.168.11.5,192.168.11.6}')
check "the prune CronJob renders the script (its listing guard there)" \
  "$(printf '%s\n' "$out" | grep -c 'nothing removed"; exit 1; }')" 1
# the server's side: the named collection's keys from its environment (never a literal key), the config mounted, the
# store's keys from the backup-store secret, the store past the sidecar, its egress to the store; off by default
check "the server: backup.xml's keys from the environment, mounted in config.d, the keys from the backup-store secret" \
  "$(printf '%s\n' "$out" | grep -c 'from_env="BACKUP_STORE_\(ACCESS\|SECRET\)_KEY"') $(printf '%s\n' "$out" | grep -c 'mountPath: /etc/clickhouse-server/config.d/50-backup.xml, subPath: backup.xml') $(printf '%s\n' "$out" | grep -A3 'name: BACKUP_STORE_' | grep -c 'name: t-schnappy-clickhouse-backup-store')" \
  "2 1 2"
check "  the store past the sidecar (its three addresses only - never a port for every destination), ClickHouse's egress to them on 9000" \
  "$(printf '%s\n' "$out" | grep -c 'excludeOutboundIPRanges: 192.168.11.4/32,192.168.11.5/32,192.168.11.6/32$') $(printf '%s\n' "$out" | grep -c excludeOutboundPorts) $(printf '%s\n' "$out" | awk '/^kind: NetworkPolicy/ { n = 0 } /name: t-schnappy-clickhouse$/ { n = 1 } n && /cidr: 192.168.11.[456]\/32/ { c++ } END { print c }')" \
  "1 0 3"
# the review's (2026-11-17): nothing in the collection overridable (its url, its keys); one backup try a night; the store's
# keys a wave before the StatefulSet; the init Job not an endpoint of ClickHouse's Service
check "  the collection's url and keys not overridable (a query naming another bucket refused)" \
  "$(printf '%s\n' "$out" | grep -cE '<(url|access_key_id|secret_access_key) overridable="false"')" 3
check "  one backup try a night (backoffLimit 0); the store's keys' ExternalSecret at wave -1" \
  "$(printf '%s\n' "$out" | awk '/^kind: CronJob/ { c = 0 } /name: t-schnappy-clickhouse-backup$/ { c = 1 } c && /backoffLimit:/ { print $2; exit }') $(printf '%s\n' "$out" | awk '/^kind: ExternalSecret/ { e = 1 } /^---/ { e = 0 } e && /sync-wave:/ { print $2 }' | tr -d '"')" \
  "0 -1"
off=$(helm template t helm/schnappy-observability/ --namespace schnappy-infra --set clickhouse.enabled=true --set clickhouse.existingSecret=ch)
check "the init Job's pod: never ClickHouse's Service's selector (its template's component clickhouse-init)" \
  "$(printf '%s\n' "$off" | awk '/^kind: Job/ { j = 1 } /^---/ { j = 0 } j && /^  template:/ { t = 1 } j && t && /app.kubernetes.io\/component:/ { print $2; exit }')" clickhouse-init
check "  off by default: no backup config, no store keys, no CronJob" \
  "$(printf '%s\n' "$off" | grep -c 'backup_store\|BACKUP_STORE_\|kind: CronJob')" 0
chr() { helm template t helm/schnappy-observability/ --namespace schnappy-infra --set clickhouse.enabled=true --set clickhouse.existingSecret=ch \
  --set clickhouse.backup.enabled=true "$@" 2>&1 || true; }
check "refused: no Vault, an endpoint not the store's form, no store addresses, keep under 2" \
  "$(chr --set clickhouse.backup.endpoint=http://s:9000 --set 'clickhouse.backup.storeIps={1.2.3.4}' | grep -c 'execution error.*needs vault.secretsEnabled') $(chr --set vault.secretsEnabled=true --set clickhouse.backup.endpoint=s:9000/x --set 'clickhouse.backup.storeIps={1.2.3.4}' | grep -c 'execution error.*backup.endpoint') $(chr --set vault.secretsEnabled=true --set clickhouse.backup.endpoint=http://s:9000 | grep -c 'execution error.*storeIps') $(chr --set vault.secretsEnabled=true --set clickhouse.backup.endpoint=http://s:9000 --set 'clickhouse.backup.storeIps={1.2.3.4}' --set clickhouse.backup.keep=1 | grep -c 'execution error.*keep')" \
  "1 1 1 1"
[ "$fails" -eq 0 ] && echo "clickhouse backup prune test: OK" || { echo "clickhouse backup prune test: $fails FAILED"; exit 1; }
