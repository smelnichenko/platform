#!/bin/sh
# The reports server's nginx as the chart renders it (reports-nginx-render.sh), in the chart's own nginx image (the
# step's, checked against values.yaml): nginx -t takes it, and it serves against a fake object store on 127.0.0.1:9000 -
# a directory's URL its index.html, asked of the store by its path exactly (no doubled slash), a file as it is, a bare
# path redirected to its directory (the wave-patches review, 2026-11-28: a variable in proxy_pass with no resolver
# failed each request, and ${uri} doubled the slash)
set -eu
chart=$(sed -n '/^reports:/,/^[a-z]/s/^  image: *//p' helm/schnappy-observability/values.yaml)
[ -n "${CI_STEP_IMAGE_CHECK:-}" ] && [ "$CI_STEP_IMAGE_CHECK" = "$chart" ] \
  || { echo "FAIL the step's image (${CI_STEP_IMAGE_CHECK:-unset}) is not the chart's reports nginx ($chart)"; exit 1; }
conf=$PWD/.ci-out/reports-nginx.conf
[ -s "$conf" ] || { echo "FAIL the rendered config is missing (reports-nginx-render.sh)"; exit 1; }
nginx -t -c "$conf" 2>&1 || { echo "FAIL nginx refused the chart's reports config"; exit 1; }
mkdir -p /tmp/s3/hyperfoil-reports/run1
echo run1-index > /tmp/s3/hyperfoil-reports/run1/index.html
echo '{"a": 1}' > /tmp/s3/hyperfoil-reports/run1/a.json
cat > /tmp/s3.conf <<'S3'
worker_processes 1;
pid /tmp/s3.pid;
error_log /tmp/s3.err warn;
events { worker_connections 16; }
http {
  access_log /tmp/s3.log;
  client_body_temp_path /tmp/s3-body; proxy_temp_path /tmp/s3-proxy; fastcgi_temp_path /tmp/s3-fcgi;
  uwsgi_temp_path /tmp/s3-uwsgi; scgi_temp_path /tmp/s3-scgi;
  server { listen 127.0.0.1:9000; root /tmp/s3; }
}
S3
nginx -c /tmp/s3.conf
nginx -c "$conf"
trap 'nginx -c "$conf" -s stop 2> /dev/null || true; nginx -c /tmp/s3.conf -s stop 2> /dev/null || true' EXIT
i=0
until wget -qO /dev/null http://127.0.0.1:8080/run1/a.json 2> /dev/null; do
  i=$((i + 1)); [ "$i" -le 20 ] || { echo "FAIL the reports server not answering"; cat /tmp/error.log; exit 1; }; sleep 0.5
done
fails=0
check() { if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1: got '$2', want '$3'"; fails=$((fails + 1)); fi; }
check "a directory's URL: its index.html" "$(wget -qO- http://127.0.0.1:8080/run1/)" "run1-index"
check "  asked of the store by its path exactly (no doubled slash)" \
  "$(grep -c '"GET /hyperfoil-reports/run1/index.html ' /tmp/s3.log) $(grep -c '//' /tmp/s3.log)" "1 0"
check "a file as it is" "$(wget -qO- http://127.0.0.1:8080/run1/a.json)" '{"a": 1}'
# busybox's wget follows the redirect; -S shows the 301 before the directory's answer
check "a bare path redirected to its directory, then served" \
  "$(wget -S -O - http://127.0.0.1:8080/run1 2>&1 | grep -c -e ' 301 ' -e '^run1-index$')" "2"
[ "$fails" = 0 ] || exit 1
echo "PASS the reports nginx serves the store as the chart configures it"
