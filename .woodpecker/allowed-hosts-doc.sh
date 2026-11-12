#!/bin/sh
# masi's allow-list and its documentation in one step: every host of masiService.http.allowedHosts (helm/schnappy/values.yaml)
# has a row in docs/masi-allowed-hosts.md, and every row there is a host of the list. A host added or removed on one side
# only fails here - the table is how a host's reason is kept (2026-11-12: 42 hosts, none written down).
# Usage: sh .woodpecker/allowed-hosts-doc.sh [values.yaml] [doc.md]
set -eu
values=${1:-helm/schnappy/values.yaml}
doc=${2:-docs/masi-allowed-hosts.md}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
# the list: the block under "allowedHosts:", its "- host" lines until the indentation drops back
awk '
  /^[ ]*allowedHosts:[ ]*$/ { match($0, /^ */); ind = RLENGTH; on = 1; next }
  on && /^[ ]*$/ { next }
  on { match($0, /^ */); if (RLENGTH <= ind) { on = 0; next } }
  on && /^[ ]*- / { sub(/^[ ]*- */, ""); sub(/[ ]*#.*$/, ""); gsub(/["'\'']/, ""); print }
' "$values" | sort > "$tmp/list"
# the table: rows whose first cell is a backticked host, under "## The chart's list"
awk '
  /^## / { on = ($0 == "## The chart'\''s list") ; next }
  on && /^\| `[^`]+` \|/ { h = $0; sub(/^\| `/, "", h); sub(/`.*$/, "", h); print h }
' "$doc" | sort > "$tmp/doc"
[ -s "$tmp/list" ] || { echo "no allowedHosts list found in $values" >&2; exit 1; }
[ -s "$tmp/doc" ] || { echo "no host table found in $doc" >&2; exit 1; }
dups=$(uniq -d "$tmp/doc")
sort -u "$tmp/doc" > "$tmp/docu"
missing=$(comm -23 "$tmp/list" "$tmp/docu")
extra=$(comm -13 "$tmp/list" "$tmp/docu")
rc=0
[ -z "$missing" ] || { echo "on the list, not documented in $doc:"; echo "$missing" | sed 's/^/  /'; rc=1; }
[ -z "$extra" ] || { echo "documented in $doc, not on the list:"; echo "$extra" | sed 's/^/  /'; rc=1; }
[ -z "$dups" ] || { echo "documented twice in $doc:"; echo "$dups" | sed 's/^/  /'; rc=1; }
[ $rc = 0 ] && echo "allowed hosts: $(wc -l < "$tmp/list") on the list, each documented"
exit $rc
