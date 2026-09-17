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

until pg_isready -q; do sleep 1; done

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

echo "init-users script test: OK ($(echo "$names" | wc -l) databases)"
