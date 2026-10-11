#!/bin/sh
# Runs the rendered sonarqube-setup hook script (.ci-out/sonarqube-setup.sh, written by chart-render-checks.sh) against
# a stub curl that answers as SonarQube and Vault do, per scenario, and logs every call with its body. What the hook
# must guarantee: the generated token reaches Vault; a token Vault never confirmed is revoked and the hook fails
# (whatever ended it - a write refused, a time-out); a failed read fails the hook with nothing created (never read as
# "absent"); the gates are set every run; the sidecar is told to quit on success only (a failed try is restarted in
# the same pod, its proxy gone if told to quit); a token generated late, after the first revoke, is revoked too; a TERM
# (the Job's deadline, an eviction) still revokes. A new version's database migration is started once (as admin only
# when refused unauthenticated), never over one running or one whose start went unanswered but taken, started again when
# its start was lost, and one failing - however it shows - fails the hook at once. Each run its own limit; sleep stubbed.
set -u
script=.ci-out/sonarqube-setup.sh
[ -s "$script" ] || { echo "sonarqube setup script test: FAIL: $script missing (run chart-render-checks.sh)" >&2; exit 1; }
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fail() { echo "sonarqube setup script test: FAIL: $*" >&2; exit 1; }
mkdir -p "$work/bin"
cat > "$work/bin/curl" <<'STUB'
#!/bin/sh
# the stub: the URL is the argument with :// in it, the body the one after -d; scenario in $SCENARIO; each call logged
url="" body="" prev="" user=""
for a; do
  case $a in *://*) url=$a ;; esac
  [ "$prev" = -d ] && body=$a
  [ "$prev" = -u ] && user=yes
  prev=$a
done
echo "$url $body${user:+ auth}" >> "$CALLS"
has() { case " $SCENARIO " in *" $1 "*) return 0 ;; esac; return 1; }
fails() { if has "$1"; then echo "curl: (22) The requested URL returned error: 500" >&2; exit 22; fi; }
# a migration scenario: the status poll's number n, the poll the migration was started at s (0: not started)
n=$(cat "$CALLS.polls" 2>/dev/null || echo 0)
s=$(cat "$CALLS.started" 2>/dev/null || echo 0)
phase() {  # the migration's phase at poll n: needed, racing (started elsewhere, the status lagging), running, done, failed
  if has restarted-failed; then echo failed; return; fi
  if has already-running; then if [ "$n" -le 2 ]; then echo racing; else echo done; fi; return; fi
  if [ "$s" = 0 ]; then echo needed; return; fi
  if has lagging; then if [ "$n" -le $((s + 2)) ]; then echo needed; else echo done; fi; return; fi
  if has fails-later; then if [ "$n" -le $((s + 1)) ]; then echo running; else echo failed; fi; return; fi
  if [ "$n" -le $((s + 1)) ]; then echo running; else echo done; fi
}
case $url in
  *quitquitquit) exit 0 ;;
  */api/system/status)
    has migration || { echo '{"status":"UP"}'; exit 0; }
    n=$((n + 1)); echo "$n" > "$CALLS.polls"
    case $(phase) in
      needed | racing) echo '{"status":"DB_MIGRATION_NEEDED"}' ;;
      running) echo '{"status":"DB_MIGRATION_RUNNING"}' ;;
      done) echo '{"status":"UP"}' ;;
      failed) echo '{"status":"DOWN"}' ;;
    esac ;;
  */api/system/db_migration_status)
    case $(phase) in
      needed) echo '{"state":"MIGRATION_NEEDED"}' ;;
      racing | running) echo '{"state":"MIGRATION_RUNNING"}' ;;
      done) echo '{"state":"MIGRATION_SUCCEEDED"}' ;;
      failed) echo '{"state":"MIGRATION_FAILED"}' ;;
    esac ;;
  */api/system/migrate_db)
    # its answer as curl -w '\n%{http_code}' prints it
    if has needs-admin && [ -z "$user" ]; then printf '{"errors":[{"msg":"Insufficient privileges"}]}\n401'; exit 0; fi
    if has start-refused; then printf '{"errors":[]}\n500'; exit 0; fi
    if has start-fails; then printf '{"state":"MIGRATION_FAILED"}\n200'; exit 0; fi
    # start-lost: the first start times out and never reached SonarQube - nothing started
    if has start-lost && [ ! -e "$CALLS.lost" ]; then : > "$CALLS.lost"; echo "curl: (28) Operation timed out" >&2; exit 28; fi
    echo "$n" > "$CALLS.started"
    if has start-unanswered; then echo "curl: (28) Operation timed out" >&2; exit 28; fi
    printf '{"state":"MIGRATION_RUNNING"}\n200' ;;
  */api/authentication/validate) echo '{"valid":false}' ;;
  */api/user_tokens/search)
    fails tokens-read
    # generate-late: the timed-out generate commits after the first revoke - the next search finds it
    if has generate-late && [ -e "$CALLS.revoked" ] && [ ! -e "$CALLS.late" ]; then : > "$CALLS.late"; : > "$CALLS.token"; fi
    if has token-exists || [ -e "$CALLS.token" ]; then echo '{"userTokens":[{"name":"ci"}]}'; else echo '{"userTokens":[]}'; fi ;;
  */api/user_tokens/generate)
    case " $SCENARIO " in
      *" generate-times-out "* | *" generate-late "*) echo "curl: (28) Operation timed out" >&2; exit 28 ;;
      *" no-token "*) echo '{}' ;;
      *" killed-in-generate "*) : > "$CALLS.token"; : > "$CALLS.generating"; /bin/sleep 2; echo '{"token":"squ_secret"}' ;;
      *) : > "$CALLS.token"; echo '{"token":"squ_secret"}' ;;
    esac ;;
  */api/user_tokens/revoke) fails revoke-fails; : > "$CALLS.revoked"; rm -f "$CALLS.token"; exit 0 ;;
  */v1/*/woodpecker-ci)
    case " $SCENARIO " in
      *" vault-fails "*) echo "curl: (28) Operation timed out" >&2; exit 28 ;;
      *" vault-no-version "*) echo '{"errors":[]}' ;;
      *) echo '{"data":{"version":3}}' ;;
    esac ;;
  */api/qualitygates/list)
    fails gates-read
    case " $SCENARIO " in *" fresh-sq "*) echo '{"qualitygates":[]}' ;;
      *) echo '{"qualitygates":[{"name":"Service"},{"name":"Frontend"}]}' ;; esac ;;
  */api/qualitygates/show*) echo '{"conditions":[{"id":"7","metric":"new_coverage"}]}' ;;
  */api/qualitygates/select) fails select-fails; echo '{}' ;;
  */api/projects/search*)
    fails project-read
    case " $SCENARIO " in *" fresh-sq "*) echo '{"components":[]}' ;; *) echo '{"components":[{"key":"p1"}]}' ;; esac ;;
  *) echo '{}' ;;
esac
STUB
chmod +x "$work/bin/curl"
printf '#!/bin/sh\nexit 0\n' > "$work/bin/sleep"
chmod +x "$work/bin/sleep"
run() {  # run <scenario words>: the script's exit status (its own limit: a hang is a failure); its calls logged
  name=$(echo "$*" | tr ' ' '_')
  : > "$work/$name.calls"
  PATH="$work/bin:$PATH" CALLS="$work/$name.calls" SCENARIO="$*" SQ_URL=http://sq SQ_ADMIN_PASSWORD=pw VAULT_TOKEN=t \
    VAULT_ADDR=https://vault timeout 60 sh "$script" > "$work/$name.out" 2>&1
}
calls() { grep -c -- "$2" "$work/$(echo "$1" | tr ' ' '_').calls"; }
out() { tail -3 "$work/$(echo "$1" | tr ' ' '_').out"; }

run fresh; rc=$?
[ "$rc" = 0 ] || fail "a first run exited $rc: $(out fresh)"
[ "$(calls fresh 'user_tokens/generate name=ci&type=USER_TOKEN')" = 1 ] || fail "a first run did not generate 'ci'"
[ "$(calls fresh 'woodpecker-ci {"data":{"sonar_token":"squ_secret"}}')" = 1 ] \
  || fail "a first run did not write the generated token to Vault"
[ "$(calls fresh user_tokens/revoke)" = 0 ] || fail "a first run revoked the token Vault got"
[ "$(calls fresh 'set_as_default name=Service')" = 1 ] && [ "$(calls fresh 'update_condition id=7&metric=new_coverage&op=LT&error=70')" = 1 ] \
  || fail "the gates' settings not set on a run that found them"
[ "$(calls fresh quitquitquit)" = 1 ] || fail "a first run did not tell the sidecar to quit"

# failing: revoked, the sidecar left running (the Job restarts this container in the same pod, through its proxy)
for sc in vault-fails vault-no-version generate-times-out; do
  run $sc; rc=$?
  [ "$rc" != 0 ] || fail "$sc: exited 0 (the token lost for good)"
  [ "$(calls "$sc" 'user_tokens/revoke name=ci')" -ge 1 ] && [ ! -e "$work/$sc.calls.token" ] \
    || fail "$sc: the token Vault never confirmed not revoked"
  [ "$(calls "$sc" quitquitquit)" = 0 ] || fail "$sc: the sidecar told to quit on a failure - the restarted try has no proxy"
done
# a generate that timed out here and committed after the first revoke: revoked again, none left, nothing said
run generate-late; rc=$?
[ "$rc" != 0 ] && [ ! -e "$work/generate-late.calls.token" ] && [ "$(calls generate-late 'user_tokens/revoke name=ci')" -ge 2 ] \
  || fail "a token generated after the first revoke left in place (rc $rc, $(calls generate-late user_tokens/revoke) revokes)"
! grep -q "revoke it by hand" "$work/generate-late.out" || fail "a late token revoked, yet said to be left"
# TERM in the middle of the generate (the Job's deadline, an eviction): the token revoked all the same, 143
name=killed-in-generate; : > "$work/$name.calls"
PATH="$work/bin:$PATH" CALLS="$work/$name.calls" SCENARIO="$name" SQ_URL=http://sq SQ_ADMIN_PASSWORD=pw VAULT_TOKEN=t \
  VAULT_ADDR=https://vault timeout 60 sh "$script" > "$work/$name.out" 2>&1 &
pid=$!
for i in $(seq 1 100); do [ -e "$work/$name.calls.generating" ] && break; /bin/sleep 0.1; done
kill -TERM "$pid"; wait "$pid"; rc=$?
[ "$rc" = 143 ] && [ ! -e "$work/$name.calls.token" ] && [ "$(calls $name quitquitquit)" = 0 ] \
  || fail "a TERM during the generate: rc $rc, token left: $([ -e "$work/$name.calls.token" ] && echo yes || echo no)"
run vault-fails revoke-fails; rc=$?
[ "$rc" != 0 ] || fail "a revoke failing after a Vault write failing exited 0"
grep -q "revoke it by hand" "$work/vault-fails_revoke-fails.out" || fail "a failed revoke not said"

run no-token; rc=$?
[ "$rc" != 0 ] || fail "a generate answering no token exited 0"
[ "$(calls no-token woodpecker-ci)" = 0 ] || fail "a generate answering no token wrote Vault"

# each read failing (the token in place for the later ones): non-zero, and nothing made after it
for sc in tokens-read "token-exists gates-read" "token-exists project-read"; do
  run $sc; rc=$?
  [ "$rc" != 0 ] || fail "$sc: exited 0 (read as absent)"
  [ "$(calls "$sc" user_tokens/generate)$(calls "$sc" qualitygates/copy)$(calls "$sc" projects/create)" = 000 ] \
    || fail "$sc: went on to create"
done
run select-fails; rc=$?
[ "$rc" != 0 ] || fail "a project's gate not selected: exited 0"

run fresh-sq; rc=$?
[ "$rc" = 0 ] || fail "a fresh SonarQube: exited $rc: $(out fresh-sq)"
[ "$(calls fresh-sq 'qualitygates/copy sourceName=Sonar%20way&name=Service')" = 1 ] \
  && [ "$(calls fresh-sq 'qualitygates/copy sourceName=Sonar%20way&name=Frontend')" = 1 ] \
  && [ "$(calls fresh-sq 'projects/create project=p1&name=P%20one&visibility=private')" = 1 ] \
  && [ "$(calls fresh-sq 'qualitygates/select gateName=Service&projectKey=p1')" = 1 ] \
  || fail "a fresh SonarQube: its gates and project not made"

run token-exists; rc=$?
[ "$rc" = 0 ] || fail "a run with the token in place exited $rc: $(out token-exists)"
[ "$(calls token-exists user_tokens/generate)" = 0 ] || fail "an existing token was generated again"

# a new version: its database migration started once, unauthenticated as /setup does, then waited for until UP
run migration; rc=$?
[ "$rc" = 0 ] || fail "a migration needed: exited $rc: $(out migration)"
[ "$(calls migration migrate_db)" = 1 ] && [ "$(calls migration 'migrate_db  auth')" = 0 ] \
  || fail "a migration needed: not started once, unauthenticated"
grep -q 'SonarQube is UP (its database migrated)' "$work/migration.out" || fail "a migration needed: its end not said"
# SonarQube still saying NEEDED two passes after it answered RUNNING: not started again
run migration lagging; rc=$?
[ "$rc" = 0 ] && [ "$(calls 'migration lagging' migrate_db)" = 1 ] \
  || fail "a lagging status: exited $rc, $(calls 'migration lagging' migrate_db) starts"
# refused unauthenticated: started as admin, once
run migration needs-admin; rc=$?
[ "$rc" = 0 ] && [ "$(calls 'migration needs-admin' migrate_db)" = 2 ] \
  && [ "$(calls 'migration needs-admin' 'migrate_db  auth')" = 1 ] \
  || fail "a start refused unauthenticated: exited $rc, not retried once as admin"
# a start nobody answered (it started all the same): its state read again, never started blind a second time
run migration start-unanswered; rc=$?
[ "$rc" = 0 ] && [ "$(calls 'migration start-unanswered' migrate_db)" = 1 ] \
  || fail "an unanswered start: exited $rc, $(calls 'migration start-unanswered' migrate_db) starts"
# a start that never reached SonarQube (lost, timed out): started again at the next pass - once more, not given up
run migration start-lost; rc=$?
[ "$rc" = 0 ] && [ "$(calls 'migration start-lost' migrate_db)" = 2 ] \
  || fail "a lost start: exited $rc, $(calls 'migration start-lost' migrate_db) starts"
# one running already - an earlier container of this Job started it - while the status still says NEEDED: not started
run migration already-running; rc=$?
[ "$rc" = 0 ] && [ "$(calls 'migration already-running' migrate_db)" = 0 ] \
  || fail "a migration already running: exited $rc, $(calls 'migration already-running' migrate_db) starts"
# failing, however it shows (the start's answer, a refusal, later while running, a restarted container finding it
# failed): 1, saying the migration failed or was not started - a wait that went on ends "not ready" (sleep stubbed)
for sc in "migration start-fails" "migration start-refused" "migration fails-later" "migration restarted-failed"; do
  run $sc; rc=$?
  [ "$rc" = 1 ] || fail "$sc: exited $rc, not 1 at once"
  grep -q 'ERROR: the database migration failed\|ERROR: database migration not started' \
    "$work/$(echo "$sc" | tr ' ' '_').out" || fail "$sc: the failure not said: $(out "$sc")"
done
[ "$(calls 'migration restarted-failed' migrate_db)" = 0 ] || fail "a failed migration started again"
[ "$(calls 'migration fails-later' api/system/status)" = 3 ] || fail "a migration failing while running not seen at once"

echo "sonarqube setup script test: OK"
