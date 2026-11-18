#!/usr/bin/env python3
"""Every chart's hook-templates ConfigMap hashes what each of its sync hooks runs, and only that (chart-render-checks.sh
runs this). A hook's key hashes its template and the templates of the ConfigMaps it mounts that the chart renders (a
ClickHouse schema in another ConfigMap changed alone never re-ran clickhouse-init - the s3gw bug's class). Checked, per
chart, by changing its copy:
  - every ConfigMap a sync hook mounts that the chart renders is among its key's templates;
  - a comment in any template a key hashes moves no hash (a k6 comment would run the smoke test against production);
  - an object added to a template moves exactly the keys that hash that template, each to a new hash.
Usage: hook-hash-check.py <work dir>    exit 1 with the findings said."""
import os
import re
import shutil
import subprocess
import sys

import yaml

# each chart with sync hooks, rendered with its hooks on (as chart-render-checks.sh renders them)
CHARTS = {
    "schnappy-data": ["--set", "postgres.password=test", "--set", "vault.secretsEnabled=true", "--set", "cnpg.enabled=true",
                      "--set", "postgres.databases[0].name=a", "--set", "postgres.databases[0].user=a",
                      "--set", "s3gw.enabled=true", "--set", "s3gw.existingSecret=s", "--set", "s3gw.storage.size=1Gi",
                      "--set", "scyllaOperator.enabled=true", "--set", "scyllaOperator.version=x",
                      "--set", "scyllaOperator.agentVersion=x"],
    "schnappy-observability": ["--set", "clickhouse.enabled=true", "--set", "clickhouse.password=x"],
    "schnappy-sonarqube": ["--set", "sonarqube.enabled=true", "--set", "sonarqube.postgres.password=x"],
    "schnappy": ["--set", "site.dnsResolver=10.43.0.10"],
}
HOOK = re.compile(r"(Pre|Post)?Sync\b")
work = sys.argv[1]
bad = []


def render(chart_dir, args, only=None):
    cmd = ["helm", "template", "t", chart_dir] + args + (["--show-only", only] if only else [])
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        sys.exit("%s did not render: %s" % (chart_dir, r.stderr.strip()[-300:]))
    return r.stdout


def hashes(chart_dir, args):
    d = yaml.safe_load(render(chart_dir, args, "templates/hook-templates.yaml")) or {}
    return d.get("data") or {}


def keys_of(chart_dir):
    """key -> the templates its hash reads, from the hook-templates source"""
    src = open(os.path.join(chart_dir, "templates/hook-templates.yaml")).read()
    out = {}
    for m in re.finditer(r'(?m)^  ([A-Za-z0-9._-]+\.ya?ml): \{\{ include "schnappy\.hookHash" (.*)\| quote \}\}$', src):
        out[m.group(1)] = re.findall(r'"/([A-Za-z0-9._-]+\.ya?ml)"', m.group(2))
    return out


for chart, args in CHARTS.items():
    cdir = os.path.join("helm", chart)
    keys = keys_of(cdir)
    if not keys:
        bad.append("%s: no key read from hook-templates.yaml" % chart)
        continue
    for k, tpls in keys.items():
        if not tpls or tpls[0] != k:
            bad.append("%s: %s hashes %s - its own template first" % (chart, k, tpls))
    # the ConfigMaps each sync hook mounts, by the template that renders them
    docs = []
    for chunk in re.split(r"(?m)^---\s*$", render(cdir, args)):
        src = re.search(r"(?m)^# Source: [^/]+/templates/(\S+)$", chunk)
        d = yaml.safe_load(chunk)
        if src and isinstance(d, dict):
            docs.append((src.group(1), d))
    cm_tpl = {d["metadata"]["name"]: s for s, d in docs if d.get("kind") == "ConfigMap"}
    for s, d in docs:
        ann = (d.get("metadata") or {}).get("annotations") or {}
        if d.get("kind") != "Job" or not (HOOK.search(ann.get("argocd.argoproj.io/hook", ""))
                                          or re.search(r"install|upgrade", ann.get("helm.sh/hook", ""))):
            continue
        vols = (((d.get("spec") or {}).get("template") or {}).get("spec") or {}).get("volumes") or []
        names = [v["configMap"]["name"] for v in vols if "configMap" in v]
        names += [p["configMap"]["name"] for v in vols if "projected" in v for p in v["projected"].get("sources") or []
                  if "configMap" in p]
        for n in names:
            t = cm_tpl.get(n)
            if t and t != s and t not in keys.get(s, []):
                bad.append("%s: %s mounts ConfigMap %s (%s), not in its hash" % (chart, s, n, t))
    # the copy: a comment moves nothing; an object moves the keys hashing that template, each anew
    base = hashes(cdir, args)
    if set(base) != set(keys):
        bad.append("%s: keys rendered %s, hashed by schnappy.hookHash %s - every key one" % (chart, sorted(base), sorted(keys)))
    for t in sorted({t for ts in keys.values() for t in ts}):
        copy = os.path.join(work, "hookhash", chart)
        shutil.rmtree(copy, ignore_errors=True)
        shutil.copytree(cdir, copy)
        path = os.path.join(copy, "templates", t)
        with open(path, "a") as f:
            f.write("\n# a comment\n")
        after = hashes(copy, args)
        if after != base:
            bad.append("%s: a comment in %s moved %s" % (chart, t, sorted(k for k in base if after.get(k) != base[k])))
        with open(path, "a") as f:
            f.write("---\napiVersion: v1\nkind: ConfigMap\nmetadata:\n  name: hookchk-object\n")
        after = hashes(copy, args)
        moved = sorted(k for k in base if after.get(k) != base[k])
        want = sorted(k for k, ts in keys.items() if t in ts)
        if moved != want:
            bad.append("%s: an object added to %s moved %s, not %s" % (chart, t, moved, want))
        if any(not re.fullmatch(r"[0-9a-f]{64}", str(after.get(k, ""))) for k in want):
            bad.append("%s: %s's hashes not sha256 after the change" % (chart, t))
for b in bad:
    print(b, file=sys.stderr)
print("hook hash check: " + ("OK" if not bad else "%d FAILED" % len(bad)))
sys.exit(1 if bad else 0)
