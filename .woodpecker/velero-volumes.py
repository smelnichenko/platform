"""Every backup.velero.io/backup-volumes annotation names volumes its pod has.

Velero's file-system backup is opt-in here (defaultVolumesToFsBackup false): a pod's annotation lists the volumes to
copy, and a name the pod has no volume of is skipped without a word - Grafana's said "data" while its volume is
"storage" (found 2026-11-18). An operator's pods are named by the operator: CNPG's data volume is pgdata, Scylla
Operator's data, Strimzi's JBOD volumes data-<id> (its pool's storage).

The operators' volume names read from production's pods (2026-11-18): CNPG's instance pgdata, scratch-data, shm;
Scylla's data, shared; Strimzi's broker data (persistent-claim storage - JBOD's are data-<id>).

usage: velero-volumes.py [--expect <Kind/name>]... <render>...
  exit 3: an annotation names a volume its pod lacks; 4: an --expect pod carries no annotation in the renders (a render
  that lost its component - a flag dropped - would otherwise pass by seeing nothing)
"""
import sys

import yaml

KEY = "backup.velero.io/backup-volumes"


def pods(doc):
    """(kind/name, annotation value, the pod's volume names) for each pod template carrying the annotation."""
    kind, meta, spec = doc.get("kind"), doc.get("metadata") or {}, doc.get("spec") or {}
    name = kind + "/" + str(meta.get("name"))
    if kind in ("Deployment", "StatefulSet", "DaemonSet", "ReplicaSet", "Job", "CronJob"):
        t = ((spec.get("jobTemplate") or {}).get("spec") or {}).get("template") if kind == "CronJob" else spec.get("template")
        t = t or {}
        ann = ((t.get("metadata") or {}).get("annotations") or {}).get(KEY)
        if ann is not None:
            vols = {v.get("name") for v in (t.get("spec") or {}).get("volumes") or []}
            vols |= {(c.get("metadata") or {}).get("name") for c in spec.get("volumeClaimTemplates") or []}
            yield name, ann, vols
    elif kind == "Cluster" and doc.get("apiVersion", "").startswith("postgresql.cnpg.io/"):
        ann = ((spec.get("inheritedMetadata") or {}).get("annotations") or {}).get(KEY)
        if ann is not None:
            yield name, ann, {"pgdata", "scratch-data", "shm"} | ({"pg-wal"} if spec.get("walStorage") else set())
    elif kind == "ScyllaCluster":
        ann = ((spec.get("podMetadata") or {}).get("annotations") or {}).get(KEY)
        if ann is not None:
            yield name, ann, {"data", "shared"}
    elif kind in ("Kafka", "KafkaNodePool"):
        tpl = (spec.get("kafka") or {}).get("template") if kind == "Kafka" else spec.get("template")
        ann = ((((tpl or {}).get("pod") or {}).get("metadata") or {}).get("annotations") or {}).get(KEY)
        if ann is not None:
            st = (spec.get("kafka") or {}).get("storage") if kind == "Kafka" else spec.get("storage")
            vols = st.get("volumes") if (st or {}).get("type") == "jbod" else None
            yield name, ann, {"data-%s" % v.get("id", 0) for v in vols} if vols else {"data"}


def main(*args):
    expect, paths, it = set(), [], iter(args)
    for a in it:
        if a == "--expect":
            expect.add(next(it))
        else:
            paths.append(a)
    bad, seen = [], set()
    for p in paths:
        with open(p) as f:
            for d in yaml.safe_load_all(f):
                if not isinstance(d, dict):
                    continue
                for name, ann, vols in pods(d):
                    seen.add(name)
                    missing = [v.strip() for v in str(ann).split(",") if v.strip() and v.strip() not in vols]
                    if missing:
                        bad.append("%s: %s names %s - its volumes: %s" % (name, KEY, missing, sorted(v for v in vols if v)))
    for b in bad:
        print(b, file=sys.stderr)
    lost = sorted(expect - seen)
    if lost:
        print("no annotated pod in the renders for: %s (seen: %s)" % (", ".join(lost), ", ".join(sorted(seen))), file=sys.stderr)
    return 3 if bad else 4 if lost else 0


if __name__ == "__main__":
    sys.exit(main(*sys.argv[1:]))
