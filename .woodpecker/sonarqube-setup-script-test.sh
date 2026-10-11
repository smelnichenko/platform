#!/bin/sh
# Runs the rendered sonarqube-setup hook script (.ci-out/sonarqube-setup.sh, written by chart-render-checks.sh) against
# a stub curl that answers as SonarQube and Vault do, per scenario, and logs every call. What the hook must guarantee:
# a token Vault never got is revoked and the hook fails (an existing token is never written again); a failed read
# fails the hook with nothing created (never read as "absent"); the sidecar is told to quit whatever the outcome.
set -u
script=.ci-out/sonarqube-setup.sh
[ -s "$script" ] || { echo "sonarqube setup script test: FAIL: $script missing (run chart-render-checks.sh)" >&2; exit 1; }
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fail() { echo "sonarqube setup script test: FAIL: $*" >&2; exit 1; }
mkdir -p "$work/bin"
cat > "$work/bin/curl" <<'STUB'
#!/bin/sh
# the stub: the URL is the argument with :// in it; scenario in $SCENARIO; every call logged
url=""
for a; do case $a in *://*) url=$a ;; esac; done
echo "$url" >> "$CALLS"
case $url in
  *quitquitquit) exit 0 ;;
  */api/system/status) echo '{"status":"UP"}' ;;
  */api/authentication/validate) echo '{"valid":false}' ;;
  */api/user_tokens/search)
    [ "$SCENARIO" != read-fails ] || { echo "curl: (22) The requested URL returned error: 500" >&2; exit 22; }
    [ "$SCENARIO" = token-exists ] && echo '{"userTokens":[{"name":"ci"}]}' || echo '{"userTokens":[]}' ;;
  */api/user_tokens/generate) echo '{"token":"squ_secret"}' ;;
  */api/user_tokens/revoke) exit 0 ;;
  */v1/*/woodpecker-ci)
    [ "$SCENARIO" != vault-fails ] || { echo "curl: (28) Operation timed out" >&2; exit 28; }
    echo '{"data":{"version":3}}' ;;
  */api/qualitygates/list) echo '{"qualitygates":[{"name":"Service"},{"name":"Frontend"}]}' ;;
  */api/projects/search*) echo '{"components":[{"key":"p1"}]}' ;;
  *) echo '{}' ;;
esac
STUB
chmod +x "$work/bin/curl"
run() {  # run <scenario>: the script's exit status; its calls in $work/<scenario>.calls
  : > "$work/$1.calls"
  PATH="$work/bin:$PATH" CALLS="$work/$1.calls" SCENARIO=$1 SQ_URL=http://sq SQ_ADMIN_PASSWORD=pw VAULT_TOKEN=t \
    VAULT_ADDR=https://vault sh "$script" > "$work/$1.out" 2>&1
}
calls() { grep -c "$2" "$work/$1.calls"; }

run fresh; rc=$?
[ "$rc" = 0 ] || fail "a first run exited $rc: $(tail -3 "$work/fresh.out")"
[ "$(calls fresh user_tokens/generate)" = 1 ] && [ "$(calls fresh woodpecker-ci)" = 1 ] \
  || fail "a first run did not generate the token and write it to Vault"
[ "$(calls fresh quitquitquit)" = 1 ] || fail "a first run did not tell the sidecar to quit"

run vault-fails; rc=$?
[ "$rc" != 0 ] || fail "a Vault write failing exited 0 (the token lost for good)"
[ "$(calls vault-fails user_tokens/revoke)" = 1 ] || fail "a token Vault never got was not revoked"
[ "$(calls vault-fails quitquitquit)" = 1 ] || fail "a failed run did not tell the sidecar to quit"

run read-fails; rc=$?
[ "$rc" != 0 ] || fail "a failed read exited 0 (read as absent)"
[ "$(calls read-fails user_tokens/generate)" = 0 ] || fail "a failed read went on to generate a token"
[ "$(calls read-fails quitquitquit)" = 1 ] || fail "a failed run did not tell the sidecar to quit"

run token-exists; rc=$?
[ "$rc" = 0 ] || fail "a run with the token in place exited $rc: $(tail -3 "$work/token-exists.out")"
[ "$(calls token-exists user_tokens/generate)" = 0 ] || fail "an existing token was generated again"

echo "sonarqube setup script test: OK"
