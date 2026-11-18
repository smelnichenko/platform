"""Every mesh AuthorizationPolicy and PeerAuthentication must select a workload that runs an Istio proxy.

A policy whose selector names labels no pod carries, or only pods without a sidecar, is enforced by nothing and still
reads as a guard: 2026-11-18 found postgres (component=postgres - CNPG labels its pods component=database), Kafka
(component=kafka, gone with Strimzi), Scylla (operator pods run without a sidecar) and five more. A render cannot see
which components an environment enables, nor which namespace runs them, so the workloads are every chart's, rendered
with everything on: a policy for a workload that runs only in another namespace (ClickHouse's, in production and test
while ClickHouse runs in schnappy-infra) passes here - the live audit (pods selected, with a sidecar, per namespace)
is what catches that.

usage: mesh-selectors.py <mesh render> <workload render>...   (exit 3: a policy selects nothing that enforces it)
"""
import sys

import yaml

NO_SIDECAR = "sidecar.istio.io/inject"


def proxied(*meta):
    """No sidecar when the pod's labels or annotations set sidecar.istio.io/inject to false (injection is on by the
    namespace's istio.io/rev label everywhere the mesh renders)."""
    return not any(str((m or {}).get(NO_SIDECAR, "")).lower() == "false" for m in meta)


def workloads(doc):
    """(kind/name, pod labels, proxied) for each pod a document makes - its own template, or an operator's pods."""
    kind, meta, spec = doc.get("kind"), doc.get("metadata") or {}, doc.get("spec") or {}
    name = meta.get("name", "")
    if kind in ("Deployment", "StatefulSet", "DaemonSet", "ReplicaSet", "Job"):
        tm = (spec.get("template") or {}).get("metadata") or {}
        yield kind + "/" + name, tm.get("labels") or {}, proxied(tm.get("labels"), tm.get("annotations"))
    elif kind == "CronJob":
        tm = ((((spec.get("jobTemplate") or {}).get("spec") or {}).get("template") or {}).get("metadata")) or {}
        yield kind + "/" + name, tm.get("labels") or {}, proxied(tm.get("labels"), tm.get("annotations"))
    elif kind == "Cluster" and doc.get("apiVersion", "").startswith("postgresql.cnpg.io/"):
        im = spec.get("inheritedMetadata") or {}
        labels = dict(im.get("labels") or {}, **{"cnpg.io/cluster": name})
        yield kind + "/" + name, labels, proxied(im.get("labels"), im.get("annotations"))
    elif kind == "KafkaNodePool":
        pm = (((spec.get("template") or {}).get("pod") or {}).get("metadata")) or {}
        labels = dict(pm.get("labels") or {}, **{"strimzi.io/cluster": (meta.get("labels") or {}).get("strimzi.io/cluster", ""),
                                                 "strimzi.io/pool-name": name})
        for role in spec.get("roles") or []:
            labels["strimzi.io/%s-role" % role] = "true"
        yield kind + "/" + name, labels, proxied(pm.get("labels"), pm.get("annotations"))
    elif kind == "ScyllaCluster":
        # Scylla Operator copies the cluster's own labels onto its pods, podMetadata's over them
        pm = spec.get("podMetadata") or {}
        labels = dict(meta.get("labels") or {}, **(pm.get("labels") or {}), **{"scylla/cluster": name})
        yield kind + "/" + name, labels, proxied(pm.get("labels"), pm.get("annotations"))
    elif kind == "Gateway" and doc.get("apiVersion", "").startswith("gateway.networking.k8s.io/"):
        # Istio deploys the gateway's own Envoy, which enforces policies on it
        yield kind + "/" + name, {"gateway.networking.k8s.io/gateway-name": name}, True


def docs(path):
    with open(path) as f:
        return [d for d in yaml.safe_load_all(f) if isinstance(d, dict)]


def main(mesh_path, *workload_paths):
    pods = [w for p in (mesh_path,) + workload_paths for d in docs(p) for w in workloads(d)]
    bad = []
    for d in docs(mesh_path):
        if d.get("kind") not in ("AuthorizationPolicy", "PeerAuthentication"):
            continue
        sel = ((d.get("spec") or {}).get("selector") or {}).get("matchLabels")
        if not sel:
            continue  # namespace-wide
        hits = [w for w in pods if all(w[1].get(k) == v for k, v in sel.items())]
        what = "%s %s %s" % (d["kind"], d["metadata"]["name"], sel)
        if not hits:
            bad.append(what + " - selects no pod any chart renders")
        elif not any(w[2] for w in hits):
            bad.append(what + " - selects only pods without a sidecar: " + ", ".join(w[0] for w in hits))
    for b in bad:
        print(b, file=sys.stderr)
    return 3 if bad else 0


if __name__ == "__main__":
    sys.exit(main(*sys.argv[1:]))
