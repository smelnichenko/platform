#!/bin/sh
# The render checks' own checkers against small fixtures (chart-render-checks only feeds them today's charts, which are
# right - a checker broken to pass everything stayed green there): mesh-selectors.py names a policy for every selecting
# kind whose selector matches nothing or only proxy-less pods - a Deployment's, a CNPG cluster's, a Kafka resource's
# merged with its pool's, a Scylla cluster's, a gateway's - and refuses an empty render; velero-volumes.py names an
# annotation that names a volume its pod lacks - a Deployment's, a StatefulSet's claim template, a CronJob's, CNPG's
# with and without its WAL volume, Scylla's, Strimzi's persistent and JBOD volumes - and an expected pod not seen.
set -eu
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
fails=0
check() { if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1: got '$2', want '$3'"; fails=$((fails + 1)); fi; }
rc() { if python3 "$@" > "$T/out" 2>&1; then echo 0; else echo $?; fi; }
# the workloads every mesh case reads
cat > "$T/w.yaml" << 'EOF_W'
apiVersion: apps/v1
kind: Deployment
metadata: {name: app}
spec:
  template:
    metadata:
      labels: {app.kubernetes.io/component: app}
---
apiVersion: apps/v1
kind: Deployment
metadata: {name: bare}
spec:
  template:
    metadata:
      labels: {app.kubernetes.io/component: bare}
      annotations: {sidecar.istio.io/inject: "false"}
---
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata: {name: pg}
spec: {}
---
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata: {name: pg-bare}
spec:
  inheritedMetadata:
    annotations: {sidecar.istio.io/inject: "false"}
---
apiVersion: kafka.strimzi.io/v1
kind: Kafka
metadata: {name: kbare}
spec:
  kafka:
    template:
      pod:
        metadata:
          annotations: {sidecar.istio.io/inject: "false"}
---
apiVersion: kafka.strimzi.io/v1
kind: KafkaNodePool
metadata: {name: pool, labels: {strimzi.io/cluster: kbare}}
spec: {roles: [broker]}
---
apiVersion: kafka.strimzi.io/v1
kind: KafkaNodePool
metadata: {name: pool, labels: {strimzi.io/cluster: kok}}
spec: {roles: [broker]}
---
apiVersion: scylla.scylladb.com/v1
kind: ScyllaCluster
metadata: {name: sc, labels: {app.kubernetes.io/component: scylla}}
spec:
  podMetadata:
    annotations: {sidecar.istio.io/inject: "false"}
---
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata: {name: gw}
EOF_W
mesh() {  # mesh <kind> <selector key> <labels as YAML flow>: one object in a mesh render
  printf 'apiVersion: security.istio.io/v1\nkind: %s\nmetadata: {name: x}\nspec:\n  %s: %s\n' "$1" "$2" "$3" > "$T/m.yaml"
  rc .woodpecker/mesh-selectors.py "$T/m.yaml" "$T/w.yaml"
}
check "an AuthorizationPolicy on a proxied Deployment: passes" "$(mesh AuthorizationPolicy selector '{matchLabels: {app.kubernetes.io/component: app}}')" 0
check "an AuthorizationPolicy on nothing: named" "$(mesh AuthorizationPolicy selector '{matchLabels: {app.kubernetes.io/component: none}}') $(grep -c 'selects no pod' "$T/out")" "3 1"
check "a PeerAuthentication on a proxy-less Deployment: named" "$(mesh PeerAuthentication selector '{matchLabels: {app.kubernetes.io/component: bare}}') $(grep -c 'without a sidecar' "$T/out")" "3 1"
for k in RequestAuthentication Telemetry WasmPlugin; do
  check "a $k on nothing: named" "$(mesh $k selector '{matchLabels: {a: b}}')" 3
done
check "a Sidecar's workloadSelector on a proxied pod: passes" "$(mesh Sidecar workloadSelector '{labels: {app.kubernetes.io/component: app}}')" 0
check "a Sidecar's workloadSelector on nothing: named" "$(mesh Sidecar workloadSelector '{labels: {a: b}}')" 3
check "an EnvoyFilter's workloadSelector on nothing: named" "$(mesh EnvoyFilter workloadSelector '{labels: {a: b}}')" 3
check "  a Sidecar's labels read from its workloadSelector alone (a selector field is not its own): nothing selecting, refused" \
  "$(mesh Sidecar selector '{matchLabels: {a: b}}')" 1
check "a CNPG cluster's pods (cnpg.io/cluster): passes" "$(mesh AuthorizationPolicy selector '{matchLabels: {cnpg.io/cluster: pg}}')" 0
check "a CNPG cluster without a sidecar (its inheritedMetadata): named" "$(mesh AuthorizationPolicy selector '{matchLabels: {cnpg.io/cluster: pg-bare}}')" 3
check "Strimzi's brokers, the Kafka resource's template without a sidecar merged into its pool's: named" \
  "$(mesh AuthorizationPolicy selector '{matchLabels: {strimzi.io/cluster: kbare, strimzi.io/broker-role: "true"}}')" 3
check "  another cluster's pool, nothing said: passes" "$(mesh AuthorizationPolicy selector '{matchLabels: {strimzi.io/cluster: kok, strimzi.io/broker-role: "true"}}')" 0
check "Scylla's pods (the cluster's own labels copied) without a sidecar: named" \
  "$(mesh AuthorizationPolicy selector '{matchLabels: {app.kubernetes.io/component: scylla}}') $(grep -c 'ScyllaCluster/sc' "$T/out")" "3 1"
check "the gateway's Envoy: passes" "$(mesh AuthorizationPolicy selector '{matchLabels: {gateway.networking.k8s.io/gateway-name: gw}}')" 0
: > "$T/empty.yaml"
check "an empty workload render: refused, not passed" "$(rc .woodpecker/mesh-selectors.py "$T/m.yaml" "$T/empty.yaml")" 1
printf 'apiVersion: v1\nkind: ConfigMap\nmetadata: {name: c}\n' > "$T/nosel.yaml"
check "a mesh render with no selecting object: refused" "$(rc .woodpecker/mesh-selectors.py "$T/nosel.yaml" "$T/w.yaml")" 1

vel() {  # vel <document>: velero-volumes.py on it alone
  printf '%s\n' "$1" > "$T/v.yaml"
  rc .woodpecker/velero-volumes.py "$T/v.yaml"
}
dep='apiVersion: apps/v1
kind: Deployment
metadata: {name: d}
spec:
  template:
    metadata:
      annotations: {backup.velero.io/backup-volumes: "VOLS"}
    spec:
      volumes: [{name: storage}, {name: tmp}]'
check "a Deployment naming its volumes: passes" "$(vel "$(echo "$dep" | sed 's/VOLS/storage,tmp/')")" 0
check "a Deployment naming one it lacks: named" "$(vel "$(echo "$dep" | sed 's/VOLS/data/')") $(grep -c "names \['data'\]" "$T/out")" "3 1"
sts='apiVersion: apps/v1
kind: StatefulSet
metadata: {name: s}
spec:
  template:
    metadata:
      annotations: {backup.velero.io/backup-volumes: "VOLS"}
    spec: {}
  volumeClaimTemplates: [{metadata: {name: data}}]'
check "a StatefulSet naming its claim template: passes" "$(vel "$(echo "$sts" | sed 's/VOLS/data/')")" 0
check "a StatefulSet naming another: named" "$(vel "$(echo "$sts" | sed 's/VOLS/other/')")" 3
cj='apiVersion: batch/v1
kind: CronJob
metadata: {name: c}
spec:
  jobTemplate:
    spec:
      template:
        metadata:
          annotations: {backup.velero.io/backup-volumes: "VOLS"}
        spec:
          volumes: [{name: dump}]'
check "a CronJob naming its volume: passes; one it lacks: named" \
  "$(vel "$(echo "$cj" | sed 's/VOLS/dump/')") $(vel "$(echo "$cj" | sed 's/VOLS/data/')")" "0 3"
cnpg='apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata: {name: pg}
spec:
  inheritedMetadata:
    annotations: {backup.velero.io/backup-volumes: "VOLS"}'
check "CNPG: pgdata passes; pg-wal without WAL storage named; with it passes" \
  "$(vel "$(echo "$cnpg" | sed 's/VOLS/pgdata/')") $(vel "$(echo "$cnpg" | sed 's/VOLS/pgdata,pg-wal/')") $(vel "$(printf '%s\n  walStorage: {size: 1Gi}' "$(echo "$cnpg" | sed 's/VOLS/pgdata,pg-wal/')")")" "0 3 0"
sc='apiVersion: scylla.scylladb.com/v1
kind: ScyllaCluster
metadata: {name: sc}
spec:
  podMetadata:
    annotations: {backup.velero.io/backup-volumes: "VOLS"}'
check "Scylla: data passes, another named" "$(vel "$(echo "$sc" | sed 's/VOLS/data/')") $(vel "$(echo "$sc" | sed 's/VOLS/data-0/')")" "0 3"
kp='apiVersion: kafka.strimzi.io/v1
kind: KafkaNodePool
metadata: {name: kafka}
spec:
  STORAGE
  template:
    pod:
      metadata:
        annotations: {backup.velero.io/backup-volumes: "VOLS"}'
pc=$(echo "$kp" | sed 's/STORAGE/storage: {type: persistent-claim}/')
jb=$(echo "$kp" | sed 's/STORAGE/storage: {type: jbod, volumes: [{id: 0}, {id: 1}]}/')
check "Strimzi persistent-claim: data passes, data-0 named" "$(vel "$(echo "$pc" | sed 's/VOLS/data/')") $(vel "$(echo "$pc" | sed 's/VOLS/data-0/')")" "0 3"
check "Strimzi JBOD: data-1 passes, data-2 named" "$(vel "$(echo "$jb" | sed 's/VOLS/data-1/')") $(vel "$(echo "$jb" | sed 's/VOLS/data-2/')")" "0 3"
printf '%s\n' "$(echo "$dep" | sed 's/VOLS/storage/')" > "$T/v.yaml"
check "an expected pod with no annotation in the renders: exit 4, named" \
  "$(rc .woodpecker/velero-volumes.py --expect Deployment/d --expect Deployment/gone "$T/v.yaml") $(grep -c 'Deployment/gone' "$T/out")" "4 1"
[ "$fails" -eq 0 ] && echo "mesh checkers test: OK" || { echo "mesh checkers test: $fails FAILED"; exit 1; }
