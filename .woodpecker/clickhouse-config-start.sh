#!/bin/sh
# ClickHouse started on the chart's config and users, in the image the chart runs (the step's image, checked against
# the chart's): a config the server refuses fails here, not at production's next restart - a ttl setting beside a
# system log's own engine stopped the server at its start (26.8, 2026-10-16). Then every system log it keeps has its
# TTL (crash_log aside: a crash's record is kept) - with none they grew without end (52 GB on ten, 2026-10-16).
set -eu
chart=$(sed -n '/^clickhouse:/,/^[a-z]/s/^  image: *//p' helm/schnappy-observability/values.yaml)
[ -n "${CI_STEP_IMAGE_CHECK:-}" ] && [ "$CI_STEP_IMAGE_CHECK" = "$chart" ] \
  || { echo "FAIL the step's image (${CI_STEP_IMAGE_CHECK:-unset}) is not the chart's ClickHouse ($chart)"; exit 1; }
f=helm/schnappy-observability/files
cp "$f/clickhouse-config.xml" /etc/clickhouse-server/config.d/00-config.xml
cp "$f/clickhouse-users.xml" /etc/clickhouse-server/users.d/00-users.xml
CLICKHOUSE_PASSWORD_SHA256=$(printf ci | sha256sum | cut -d' ' -f1)
export CLICKHOUSE_PASSWORD_SHA256
clickhouse su clickhouse:clickhouse clickhouse-server --config-file=/etc/clickhouse-server/config.xml \
  > /dev/null 2>&1 &
server=$!
q() { clickhouse-client --user schnappy --password ci -q "$1"; }
i=0
until q 'select 1' > /dev/null 2>&1; do
  kill -0 "$server" 2> /dev/null || {
    echo "FAIL ClickHouse refused the chart's config:"
    grep -E '<(Error|Fatal)>' /var/log/clickhouse-server/clickhouse-server.err.log | tail -5
    exit 1
  }
  i=$((i + 1))
  [ "$i" -le 120 ] || { echo "FAIL ClickHouse not answering after 120 s"; exit 1; }
  sleep 1
done
# the server that answered is the chart's release (CI_STEP_IMAGE_CHECK is a copy of the step's image: the step's own
# image: changed alone, it still read as the chart's)
running=$(q 'select version()')
want=${chart##*:}; want=${want%%@*}; want=${want%%-*}
[ "$running" = "$want" ] || { kill "$server"; echo "FAIL the server started is ClickHouse $running, not the chart's $want"; exit 1; }
q 'SYSTEM FLUSH LOGS'
untimed=$(q "select arrayStringConcat(groupArray(name), ' ') from system.tables where database = 'system'
             and name like '%\\_log' and name != 'crash_log' and engine like '%MergeTree%'
             and position(create_table_query, ' TTL ') = 0")
logs=$(q "select count() from system.tables where database = 'system' and name like '%\\_log'")
kill "$server"
[ -z "$untimed" ] || { echo "FAIL system logs kept for ever: $untimed"; exit 1; }
[ "$logs" -ge 10 ] || { echo "FAIL only $logs system logs made - the check saw too little"; exit 1; }
echo "PASS ClickHouse $running ($chart) started on the chart's config; its $logs system logs each with a TTL (crash_log aside)"
