#!/bin/sh
# Runs three hook scripts as rendered (.ci-out/{scylla-schema,gateway-patch,preview-cleanup}.sh, written by
# chart-render-checks.sh) against stub cqlsh, kubectl and wget, per scenario. What each must guarantee: a failed or
# timed-out call fails the hook - before set -e they ran on to "done" and reported success. The Scylla schema takes a
# column that exists already as done, nothing else; the gateway's patch failing fails it; preview cleanup tells a "no"
# from can-i (skipped, said) from a failure of the check, the list, a delete or the Keycloak lookup. Each run its own limit.
set -u
for s in scylla-schema gateway-patch preview-cleanup; do
  [ -s ".ci-out/$s.sh" ] || { echo "hook scripts test: FAIL: .ci-out/$s.sh missing (run chart-render-checks.sh)" >&2; exit 1; }
done
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fail() { echo "hook scripts test: FAIL: $*" >&2; exit 1; }
mkdir -p "$work/bin"
# the stubs: scenario words in $SCENARIO; every call logged with its arguments in $CALLS
cat > "$work/bin/cqlsh" <<'STUB'
#!/bin/sh
echo "cqlsh $*" >> "$CALLS"
has() { case " $SCENARIO " in *" $1 "*) return 0 ;; esac; return 1; }
case "$*" in
  *"SELECT now()"*) exit 0 ;;
  *"ALTER TABLE"*)
    if has alter-times-out; then echo "OperationTimedOut: errors={}, last_host=scylla" >&2; exit 1; fi
    echo 'InvalidRequest: Error from server: code=2200 [Invalid query] message="Invalid column name user_uuid because it conflicts with an existing column"' >&2
    exit 2 ;;
  *) cat > /dev/null; if has create-fails; then echo "OperationTimedOut: errors={}" >&2; exit 1; fi; exit 0 ;;
esac
STUB
cat > "$work/bin/kubectl" <<'STUB'
#!/bin/sh
echo "kubectl $*" >> "$CALLS"
has() { case " $SCENARIO " in *" $1 "*) return 0 ;; esac; return 1; }
case "$*" in
  *"auth can-i"*)
    if has can-i-errors; then echo "error: the server is currently unable to handle the request" >&2; exit 1; fi
    if has can-i-no; then echo no; exit 1; fi
    echo yes ;;
  *"get kafkatopics"*)
    if has list-fails; then echo "error: timed out" >&2; exit 1; fi
    printf 'kafkatopic.kafka.strimzi.io/pr-7-chat\nkafkatopic.kafka.strimzi.io/pr-8-chat\nkafkatopic.kafka.strimzi.io/pr-7-masi\n' ;;
  *" delete "*) if has delete-fails; then echo "error: timed out" >&2; exit 1; fi ;;
  *"get svc"*) exit 0 ;;
  *"patch svc"*) if has patch-fails; then echo "error: timed out" >&2; exit 1; fi; echo "service/x patched" ;;
esac
STUB
cat > "$work/bin/wget" <<'STUB'
#!/bin/sh
echo "wget $*" >> "$CALLS"
case " $SCENARIO " in *" lookup-fails "*) case "$*" in *clientId=*) echo "wget: server returned error: HTTP/1.1 503" >&2; exit 1 ;; esac ;; esac
case "$*" in *clientId=*) echo '[{"id":"abc-123","clientId":"preview-pr-7"}]' ;; esac
STUB
printf '#!/bin/sh\nexit 0\n' > "$work/bin/sleep"
chmod +x "$work/bin/cqlsh" "$work/bin/kubectl" "$work/bin/wget" "$work/bin/sleep"
run() {  # run <script> <scenario words>: the script's exit status (its own limit); its calls logged
  script=$1; shift
  name=$script-$(echo "$*" | tr ' ' '_')
  : > "$work/$name.calls"
  PATH="$work/bin:$PATH" CALLS="$work/$name.calls" SCENARIO="$*" PR_NUMBER=7 SHARED_KAFKA_NS=kafka \
    KEYCLOAK_REALM_URL=http://kc/admin/realms/r KEYCLOAK_ADMIN_TOKEN=t timeout 60 sh ".ci-out/$script.sh" \
    > "$work/$name.out" 2>&1
}
calls() { grep -c -- "$3" "$work/$1-$(echo "$2" | tr ' ' '_').calls"; }
out() { cat "$work/$1-$(echo "$2" | tr ' ' '_').out"; }

# Scylla schema: a column that exists already is done; the CREATE or an ALTER failing fails the hook, unsaid "applied"
run scylla-schema ok; rc=$?
[ "$rc" = 0 ] && out scylla-schema ok | grep -q "Schema applied successfully" \
  || fail "scylla schema: the columns there already failed it (rc $rc): $(out scylla-schema ok | tail -3)"
for sc in create-fails alter-times-out; do
  run scylla-schema $sc; rc=$?
  [ "$rc" != 0 ] && [ "$rc" != 124 ] || fail "scylla schema, $sc: exited $rc"
  ! out scylla-schema $sc | grep -q "Schema applied successfully" || fail "scylla schema, $sc: said applied"
done

# the gateway's patch: failing fails the hook, "Done." unsaid
run gateway-patch ok; rc=$?
[ "$rc" = 0 ] && [ "$(calls gateway-patch ok 'patch svc')" = 1 ] || fail "gateway: a patch that worked exited $rc"
run gateway-patch patch-fails; rc=$?
[ "$rc" != 0 ] && [ "$rc" != 124 ] && ! out gateway-patch patch-fails | grep -q '^Done\.' \
  || fail "gateway: a failed patch exited $rc: $(out gateway-patch patch-fails | tail -2)"

# preview cleanup: its own pr-7 topics deleted, another PR's kept; a "no" skips them, said; every failure fails it
run preview-cleanup ok; rc=$?
[ "$rc" = 0 ] && [ "$(calls preview-cleanup ok ' delete kafkatopic')" = 2 ] && [ "$(calls preview-cleanup ok 'pr-8-chat')" = 0 ] \
  && [ "$(calls preview-cleanup ok 'method=DELETE')" = 1 ] \
  || fail "preview cleanup: a clean run exited $rc or deleted the wrong things: $(cat "$work/preview-cleanup-ok.calls")"
run preview-cleanup can-i-no; rc=$?
[ "$rc" = 0 ] && [ "$(calls preview-cleanup can-i-no 'get kafkatopics')" = 0 ] && out preview-cleanup can-i-no | grep -q "no right" \
  || fail "preview cleanup: a \"no\" from can-i not skipped and said (rc $rc)"
for sc in can-i-errors list-fails delete-fails lookup-fails; do
  run preview-cleanup $sc; rc=$?
  [ "$rc" != 0 ] && [ "$rc" != 124 ] || fail "preview cleanup, $sc: exited $rc - a failure read as nothing to do"
  ! out preview-cleanup $sc | grep -q "preview cleanup done" || fail "preview cleanup, $sc: said done"
done
[ "$(calls preview-cleanup lookup-fails 'method=DELETE')" = 0 ] || fail "preview cleanup: a failed lookup went on to delete"

echo "hook scripts test: OK"
