#!/bin/sh
# Runs the rendered sonarqube-setup hook script (.ci-out/sonarqube-setup.sh, written by chart-render-checks.sh) against
# a stub curl that answers as SonarQube and Vault do, per scenario, and logs every call with its body. What the hook
# must guarantee: the generated token reaches Vault; a token Vault never confirmed is revoked and the hook fails
# (whatever ended it - a write refused, a time-out); a failed read fails the hook with nothing created (never read as
# "absent"); the gates are set every run; the sidecar is told to quit whatever the outcome. Each run its own limit.
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
url="" body="" prev=""
for a; do
  case $a in *://*) url=$a ;; esac
  [ "$prev" = -d ] && body=$a
  prev=$a
done
echo "$url $body" >> "$CALLS"
fails() { case " $SCENARIO " in *" $1 "*) echo "curl: (22) The requested URL returned error: 500" >&2; exit 22 ;; esac; }
case $url in
  *quitquitquit) exit 0 ;;
  */api/system/status) echo '{"status":"UP"}' ;;
  */api/authentication/validate) echo '{"valid":false}' ;;
  */api/user_tokens/search)
    fails tokens-read
    case " $SCENARIO " in *" token-exists "*) echo '{"userTokens":[{"name":"ci"}]}' ;; *) echo '{"userTokens":[]}' ;; esac ;;
  */api/user_tokens/generate)
    case " $SCENARIO " in
      *" generate-times-out "*) echo "curl: (28) Operation timed out" >&2; exit 28 ;;
      *" no-token "*) echo '{}' ;;
      *) echo '{"token":"squ_secret"}' ;;
    esac ;;
  */api/user_tokens/revoke) fails revoke-fails; exit 0 ;;
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

for sc in vault-fails vault-no-version generate-times-out; do
  run $sc; rc=$?
  [ "$rc" != 0 ] || fail "$sc: exited 0 (the token lost for good)"
  [ "$(calls "$sc" 'user_tokens/revoke name=ci')" = 1 ] || fail "$sc: the token Vault never confirmed not revoked"
  [ "$(calls "$sc" quitquitquit)" = 1 ] || fail "$sc: the sidecar not told to quit"
done
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

echo "sonarqube setup script test: OK"
