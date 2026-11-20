#!/bin/bash
# Kafka's backup CronJob as schnappy-data renders it (helm): its image the cluster's Kafka version, its pods, store,
# guard and upload order, its NetworkPolicy and ExternalSecret; refused with tools at another version; off by default.
# And the CI step that runs the dump and restore (kafka-backup-test.sh) on the very image the CronJob runs.
set -eu
fails=0
check() { if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1: got '$2', want '$3'"; fails=$((fails + 1)); fi; }
v=$(awk '/^strimzi:/ { s = 1 } s && /^  kafkaVersion:/ { print $2; exit }' helm/schnappy-data/values.yaml)
check "the CI step for the dump and restore runs apache/kafka:$v, the CronJob's image" \
  "$(grep -c "^    image: apache/kafka:$v\$" .woodpecker/ci.yaml)" 1
kb() { helm template t helm/schnappy-data/ --namespace schnappy-production --set postgres.password=test --set strimzi.enabled=true \
  --set strimzi.backup.enabled=true --set vault.secretsEnabled=true --set alerts.enabled=true "$@" 2>&1 || true; }
out=$(kb --set strimzi.backup.endpoint=http://192.168.11.5:9000 --set 'strimzi.backup.storeIps={192.168.11.4,192.168.11.5,192.168.11.6}' \
  --set strimzi.kafkaVersion=4.3.1)
cj() { printf '%s\n' "$out" | awk '/^kind: CronJob/ { c = 1 } /^---/ { c = 0 } c'; }
check "the CronJob: the dump in apache/kafka at the cluster's version, one try a night" \
  "$(cj | grep -c 'image: apache/kafka:4.3.1$') $(cj | awk '/backoffLimit:/ { print $2; exit }')" "1 0"
check "  in the mesh with a native sidecar (Kafka's 9092 is STRICT mTLS; the proxy up before the dump's init container), the store past it" \
  "$(cj | grep -c 'sidecar.istio.io/nativeSidecar: "true"') $(cj | grep -c 'sidecar.istio.io/inject: "false"') $(cj | grep -c 'excludeOutboundIPRanges: 192.168.11.4/32,192.168.11.5/32,192.168.11.6/32$')" \
  "1 0 1"
cp_line=$(cj | grep -n 'rclone copy "/dump/$d" "$STORE/$d" --exclude DONE' | cut -d: -f1)
done_line=$(cj | grep -n 'rclone copyto "/dump/$d/DONE"' | cut -d: -f1)
check "  its own ServiceAccount (its mesh identity, for an allow-list on Kafka), no token mounted" \
  "$(printf '%s\n' "$out" | awk '/^kind: ServiceAccount/ { s = 1 } /^---/ { s = 0 } s && /^  name: .*-kafka-backup$/ { n++ } END { print n + 0 }') $(cj | grep -c 'serviceAccountName: .*-kafka-backup$') $(cj | grep -c 'automountServiceAccountToken: false')" \
  "1 1 1"
check "  the upload: the dump without DONE first, DONE after it; the prune for the dumps' layout (root, DONE)" \
  "$([ -n "$cp_line" ] && [ -n "$done_line" ] && [ "$cp_line" -lt "$done_line" ] && echo ordered || echo not-ordered) $(cj | grep -E '\{ name: (PREFIX|MARKER), value:' | tr -d ' ' | tr '\n' ';')" \
  'ordered -{name:PREFIX,value:""};-{name:MARKER,value:DONE};'
check "  the store's keys its own ExternalSecret's (Vault's backup-store), never the CNPG backup Secret" \
  "$(printf '%s\n' "$out" | awk '/^kind: ExternalSecret/ { e = 1 } /^---/ { e = 0 } e && /^  name: .*-kafka-backup-store$/ { n++ } END { print n + 0 }') $(cj | grep -A1 'secretKeyRef' | grep -c 'name: .*-kafka-backup-store')" \
  "1 2"
check "  its pods' egress to the store's three addresses on 9000; KafkaBackupsUnwatched with it" \
  "$(printf '%s\n' "$out" | awk '/^---/ { n = 0 } /^kind: NetworkPolicy/ { k = 1 } /^kind: / && !/NetworkPolicy/ { k = 0 } k && /^  name: .*-kafka-backup$/ { n = 1 } n && /cidr: 192.168.11.[456]\/32/ { c++ } n && /port: 9000/ { p++ } END { print c + 0, p + 0 }') $(printf '%s\n' "$out" | grep -c 'alert: KafkaBackupsUnwatched')" \
  "3 1 1"
check "  the dump refuses while a restore runs: the restoring ConfigMap optional, read-only at /restoring, RESTORING its key" \
  "$(cj | grep -A3 '^            - name: restoring$' | tr -d ' ' | tr '\n' ';') $(cj | grep -c '{ name: restoring, mountPath: /restoring, readOnly: true }') $(cj | grep -c '{ name: RESTORING, value: /restoring/since }')" \
  "-name:restoring;configMap:;name:t-schnappy-kafka-backup-restoring;optional:true; 1 1"
guard_line=$(cj | grep -n 'sh /scripts/guard.sh "/dump/$d"' | cut -d: -f1)
check "  the guard (Kafka holding everything the store's newest dump held) before the upload; the scratch bounded" \
  "$([ -n "$guard_line" ] && [ -n "$cp_line" ] && [ "$guard_line" -lt "$cp_line" ] && echo before || echo not-before) $(printf '%s\n' "$out" | grep -c '^  guard.sh: |$') $(cj | grep -A2 '^            - name: tmp$' | grep -c 'sizeLimit: 256Mi')" \
  "before 1 1"
up() { cj | awk '/^            - name: upload$/ { u = 1 } u && /^            - name: / && !/upload$/ { u = 0 } u'; }
check "  the upload (where the guard runs: mktemp on a read-only root) mounts its scratch at /tmp; the guard's failure never swallowed" \
  "$(up | grep -c '{ name: tmp, mountPath: /tmp }') $(up | grep -c 'readOnlyRootFilesystem: true') $(up | grep 'guard.sh' | grep -c -e '|| true' -e '; true')" "1 1 0"
check "  every container of the backup's pod mounts /tmp (the dump's tools log there, LOG_DIR; the upload's rclone and guard)" \
  "$(cj | grep -c '{ name: tmp, mountPath: /tmp }') $(cj | grep -c 'readOnlyRootFilesystem: true')" "2 2"
check "refused: no endpoint form, no store addresses, no Vault, keep under 2" \
  "$(kb --set strimzi.backup.endpoint=x --set 'strimzi.backup.storeIps={1.2.3.4}' | grep -c 'execution error.*backup.endpoint') $(kb --set strimzi.backup.endpoint=http://s:9000 | grep -c 'execution error.*storeIps') $(kb --set strimzi.backup.endpoint=http://s:9000 --set 'strimzi.backup.storeIps={1.2.3.4}' --set vault.secretsEnabled=false | grep -c 'execution error.*vault') $(kb --set strimzi.backup.endpoint=http://s:9000 --set 'strimzi.backup.storeIps={1.2.3.4}' --set strimzi.backup.keep=1 | grep -c 'execution error.*keep')" \
  "1 1 1 1"
check "refused: tools at another version than the cluster's (a mirror's path with its tag, or a digest after it, taken)" \
  "$(kb --set strimzi.backup.endpoint=http://s:9000 --set 'strimzi.backup.storeIps={1.2.3.4}' --set strimzi.kafkaVersion=4.3.1 --set strimzi.backup.toolsImage=apache/kafka:4.2.0 | grep -c 'execution error.*toolsImage') $(kb --set strimzi.backup.endpoint=http://s:9000 --set 'strimzi.backup.storeIps={1.2.3.4}' --set strimzi.kafkaVersion=4.3.1 --set strimzi.backup.toolsImage=mirror.local/apache/kafka:4.3.1 | grep -c 'image: mirror.local/apache/kafka:4.3.1$') $(kb --set strimzi.backup.endpoint=http://s:9000 --set 'strimzi.backup.storeIps={1.2.3.4}' --set strimzi.kafkaVersion=4.3.1 --set strimzi.backup.toolsImage=apache/kafka:4.3.1@sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef | grep -c 'image: apache/kafka:4.3.1@sha256:')" \
  "1 1 1"
check "off by default: no Kafka backup at all" \
  "$(helm template t helm/schnappy-data/ --set postgres.password=test --set strimzi.enabled=true | grep -c 'kafka-backup')" 0
[ "$fails" -eq 0 ] && echo "kafka backup render test: OK" || { echo "kafka backup render test: $fails FAILED"; exit 1; }
