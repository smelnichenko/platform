#!/bin/sh
# Alertmanager's config in Alertmanager's own image: amtool takes it (a merge key that lost its anchor, a receiver a
# route names and none defines, an e-mail with no address: refused here, not by production's pod - which, recreated on
# every config change, would crash-loop with no alert going out); each alert's route as production routes it; and the
# upgrade cycle's notices through Alertmanager itself - one unit's page (critical) holds back no other unit's notice,
# its own unit's warnings it does (the inhibit rule by unit: a page held every unit's veto back for a week, 2026-11-15).
set -eu
cfg=build/alertmanager/alertmanager.yml
amtool check-config "$cfg"
fail() { echo "FAIL: $*" >&2; exit 1; }
route() {  # the receivers an alert's labels reach - production's routing tree, read by amtool
  amtool config routes test --config.file="$cfg" "$@" | tail -n 1
}
[ "$(route alertname=UpgradeCycle kind=applied unit=u severity=info notice=1)" = email-notice ] || fail "a notice is not the notices' route's"
[ "$(route alertname=UpgradeCycle kind=veto unit=u severity=warning notice=1)" = email-notice ] || fail "a veto notice is not the notices' route's"
[ "$(route alertname=UpgradeCycle kind=one-way-failed unit=u severity=critical notice=1)" = email-notice ] \
  || fail "the cycle's page is not the notices' route's (the critical route's resolved mail after a week, its grouping across units)"
[ "$(route alertname=NodeDown severity=critical)" = email ] || fail "a critical alert is not the e-mail route's"
[ "$(route alertname=DiskFilling severity=warning)" = email ] || fail "a warning is not the e-mail route's"
[ "$(route alertname=Watchdog)" = null ] || fail "Watchdog is not silenced"
amtool check-config build/alertmanager/alertmanager-kagent.yml > /dev/null
[ "$(amtool config routes test --config.file=build/alertmanager/alertmanager-kagent.yml alertname=UpgradeCycle kind=one-way-failed unit=u severity=critical notice=1 | tail -n 1)" = email-notice ] \
  || fail "with kagent's investigation on, the cycle's page goes to kagent too"
# the notices' route and receiver as rendered: one mail a notice, a page hourly, never a resolved, the notice's subject
block() {  # the rendered lines from the one holding $1 up to the next matching the regex $2 (its next sibling)
  awk -v start="$1" -v stop="$2" 'index($0, start) && !n { n = 1; print; next } n { if ($0 ~ stop) exit; print }' "$cfg"
}
route_block=$(block "alertname: UpgradeCycle" '^    - ')
echo "$route_block" | grep -q "group_by: \['alertname', 'kind', 'unit'\]" || fail "the notices are not grouped by kind and unit"
echo "$route_block" | grep -q 'repeat_interval: 72h' || fail "a notice repeats before its life is over (72 h, under the 120 h kept)"
echo "$route_block" | grep -A1 'severity: critical' | grep -q 'repeat_interval: 1h' || fail "the cycle's page is not hourly"
receiver=$(block "- name: email-notice" '^  - name: |^[a-z]')
echo "$receiver" | grep -q 'send_resolved: false' || fail "the notices' receiver sends a resolved mail"
echo "$receiver" | grep -qF "Subject: '[UpgradeCycle] {{ .CommonLabels.kind }}: {{ .CommonLabels.unit }}{{ with .CommonAnnotations.summary }} - {{ . }}{{ end }}'" \
  || fail "the notices' subject is not the notice's own"
echo "$receiver" | grep -q 'to: .ops@example.org.' || fail "the notices are not mailed to the admin address"
echo "$receiver" | grep -q 'html:' || fail "the notices carry no body"
# the notices through Alertmanager itself (no cluster, no mail sent - its smarthost unreachable here)
alertmanager --config.file="$cfg" --storage.path=/tmp/am --cluster.listen-address= --web.listen-address=127.0.0.1:9093 \
  > /tmp/am.log 2>&1 &
am=$!
trap 'kill $am 2> /dev/null' EXIT
for _ in $(seq 30); do wget -qO- http://127.0.0.1:9093/-/ready > /dev/null 2>&1 && break; sleep 1; done
wget -qO- http://127.0.0.1:9093/-/ready > /dev/null 2>&1 || { cat /tmp/am.log; fail "Alertmanager did not start on the config"; }
now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
post() {  # alertname kind unit severity notice
  printf '[{"labels":{"alertname":"%s","kind":"%s","unit":"%s","severity":"%s","notice":"%s"},"startsAt":"%s"}]' \
    "$1" "$2" "$3" "$4" "$5" "$now" \
    | wget -qO- --header 'Content-Type: application/json' --post-file=/dev/stdin http://127.0.0.1:9093/api/v2/alerts > /dev/null
}
post UpgradeCycle one-way-failed alpha critical 1
post UpgradeCycle veto beta warning 2
post UpgradeCycle blocked alpha warning 3
state() {  # the alert's state: active or suppressed
  wget -qO- "http://127.0.0.1:9093/api/v2/alerts?filter=unit%3D%22$1%22&filter=notice%3D%22$2%22" \
    | sed -n 's/.*"state":"\([a-z]*\)".*/\1/p'
}
# the inhibition settles within Alertmanager's own evaluation: read until the page holds its own unit's warning back
for _ in $(seq 50); do [ "$(state alpha 3)" = suppressed ] && break; sleep 0.2; done
[ "$(state beta 2)" = active ] || fail "one unit's page holds back another unit's veto notice ($(state beta 2))"
[ "$(state alpha 3)" = suppressed ] || fail "a unit's page no longer holds back its own unit's warning ($(state alpha 3))"
echo "alertmanager config: OK"
