#!/bin/sh
# Runs the rendered schnappy-data init-users hook script against a REAL Postgres
# (the CI `postgres` service) and checks what the sync hook must guarantee.
# Input: .ci-out/init-users.sh (written by chart-render-checks.sh) and
# .ci-out/init-users.databases (one name per line); PGHOST/PGUSER/PGPASSWORD
# point at a superuser. Exit non-zero on the first broken guarantee.
set -u
script=.ci-out/init-users.sh
names=$(cat .ci-out/init-users.databases)
fail() { echo "init-users script test: FAIL: $*" >&2; exit 1; }
sql() { psql -tAX -c "$1"; }
upper() { echo "$1" | tr '[:lower:]' '[:upper:]'; }
first=$(echo "$names" | head -1); last=$(echo "$names" | tail -1)
[ -n "$first" ] || fail "no database names"

# Postgres ready within a minute, else the test fails (never a wait without an end)
for _ in $(seq 60); do pg_isready -q && break; sleep 1; done
pg_isready -q || fail "Postgres not ready in 60 s"

# Run 1: fresh cluster; one password carries a quote (the classic SQL breaker).
for n in $names; do export "DB_PASSWORD_$(upper "$n")=pw-$n"; done
export "DB_PASSWORD_$(upper "$first")=it's-$first"
sh "$script" >.ci-out/run1.log 2>&1 || fail "run 1 exited $? — $(tail -3 .ci-out/run1.log)"
for n in $names; do
  [ "$(sql "SELECT rolcanlogin FROM pg_roles WHERE rolname = '$n'")" = "t" ] || fail "role $n missing or cannot log in"
  [ "$(sql "SELECT r.rolname FROM pg_database d JOIN pg_roles r ON r.oid = d.datdba WHERE d.datname = '$n'")" = "$n" ] || fail "database $n missing or not owned by $n"
done
PGPASSWORD="it's-$first" psql -U "$first" -d "$first" -tAXc "SELECT 1" | grep -qx 1 || fail "cannot log in as $first with the quoted password"

# Run 2: idempotent re-run with rotated passwords — no CREATE, new passwords live.
for n in $names; do export "DB_PASSWORD_$(upper "$n")=rot-$n"; done
sh "$script" >.ci-out/run2.log 2>&1 || fail "run 2 exited $?"
grep -q "CREATE DATABASE" .ci-out/run2.log && fail "run 2 re-created a database"
PGPASSWORD="rot-$last" psql -U "$last" -d "$last" -tAXc "SELECT 1" | grep -qx 1 || fail "rotated password for $last not applied"
PGPASSWORD="pw-$last" psql -U "$last" -d "$last" -tAXc "SELECT 1" >/dev/null 2>&1 && fail "old password for $last still works"

# Negative 1: a missing OR EMPTY secret aborts — that role's password stays as it
# was (set -u catches only the unset case; an ExternalSecret can sync an empty key).
unset "DB_PASSWORD_$(upper "$last")"
sh "$script" >.ci-out/run3.log 2>&1 && fail "run with DB_PASSWORD_$(upper "$last") unset exited 0"
export "DB_PASSWORD_$(upper "$last")="
sh "$script" >.ci-out/run3b.log 2>&1 && fail "run with DB_PASSWORD_$(upper "$last") empty exited 0"
PGPASSWORD="rot-$last" psql -U "$last" -d "$last" -tAXc "SELECT 1" | grep -qx 1 || fail "password of $last changed by an aborted run"
export "DB_PASSWORD_$(upper "$last")=rot-$last"

# Negative 2: an SQL error inside the heredoc must fail the script (ON_ERROR_STOP),
# else a hook could report Succeeded with the role untouched.
sed "s/ALTER ROLE $first PASSWORD/ALTER ROLE no_such_role_$first PASSWORD/" "$script" >.ci-out/broken.sh
sh .ci-out/broken.sh >.ci-out/run4.log 2>&1 && fail "a failing SQL statement did not fail the script"

# Negative 3: a Postgres that never answers ends the wait at its bound, non-zero, said - not a hook waiting out its
# deadline (the bound shrunk to 3 s; 192.0.2.1 answers nothing: each try ends at its connect timeout, not TCP's)
sed 's/+ 600 ))/+ 3 ))/' "$script" >.ci-out/unreachable.sh
grep -q '+ 3 ))' .ci-out/unreachable.sh || fail "the wait's bound not found in the script"
# its own limit: a wait that never ends is a failure here, not a hang (busybox timeout: 143 when it fires)
PGHOST=192.0.2.1 PGCONNECT_TIMEOUT=1 timeout 60 sh .ci-out/unreachable.sh >.ci-out/run5.log 2>&1
rc=$?
[ "$rc" -ne 0 ] || fail "an unreachable Postgres exited 0"
[ "$rc" -ne 143 ] && [ "$rc" -ne 124 ] || fail "an unreachable Postgres: the wait did not end at its bound (killed at 60 s)"
grep -q "not ready after" .ci-out/run5.log || fail "an unreachable Postgres not said: $(tail -2 .ci-out/run5.log)"
grep -q "is ready" .ci-out/run5.log && fail "an unreachable Postgres taken for ready (the wait broke out, not failed)"

# Negative 4: a lock held elsewhere (an ALTER ROLE uncommitted) ends the script at its lock_timeout - the pod's
# PGOPTIONS (as chart-render-checks rendered them), the lock time-out shrunk to 2 s - non-zero, not a hook hanging
[ -s .ci-out/init-users.pgoptions ] || fail "the rendered PGOPTIONS missing (run chart-render-checks.sh)"
opts=$(sed 's/lock_timeout=[0-9]*s/lock_timeout=2s/' .ci-out/init-users.pgoptions)
echo "$opts" | grep -q 'lock_timeout=2s' || fail "no lock_timeout in the rendered PGOPTIONS"
{ printf 'BEGIN;\nALTER ROLE %s CONNECTION LIMIT 7;\nSELECT pg_sleep(30);\n' "$first" | psql -q > /dev/null 2>&1; } &
holder=$!
for _ in $(seq 50); do
  [ "$(sql "SELECT count(*) FROM pg_stat_activity WHERE query LIKE '%pg_sleep(30)%' AND state = 'active'")" -ge 1 ] && break
  sleep 0.1
done
t0=$(date +%s)
PGOPTIONS="$opts" timeout 25 sh "$script" > .ci-out/run6.log 2>&1
rc=$?
kill "$holder" 2> /dev/null
sql "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE query LIKE '%pg_sleep(30)%' AND pid <> pg_backend_pid()" > /dev/null
[ "$rc" -ne 0 ] || fail "a lock held elsewhere: the script exited 0"
[ "$rc" -ne 124 ] && [ "$rc" -ne 143 ] || fail "a lock held elsewhere: the script hung (no lock_timeout)"
grep -q "lock timeout" .ci-out/run6.log || fail "a lock held elsewhere: not ended by its lock_timeout: $(tail -2 .ci-out/run6.log)"

echo "init-users script test: OK ($(echo "$names" | wc -l) databases)"
