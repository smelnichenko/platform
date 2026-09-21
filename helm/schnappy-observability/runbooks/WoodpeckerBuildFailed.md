# WoodpeckerBuildFailed

**Severity:** warning

## What fired

A step of a pipeline that builds **main** failed on `$labels.repo` within the last 10 min: the `cd` workflow of an app repo (it runs only on a push to main), or the `ci` workflow of platform, infra or ops (they push to main directly). The metric is `woodpecker_step_failures_total{workflow, type!="service"}`. A failed pull-request pipeline does not fire it: that is feedback for its author, on the PR. (`woodpecker_pipeline_count` cannot be used for this — a pull request's pipeline is labelled with its target branch, so every PR counts as `main`.)

## Impact

A CI/CD build is broken on `$labels.repo`. If this is a deploy pipeline (cd.yaml), the artifact didn't build → no fresh image → next deploy uses stale code. If lint/test pipeline (ci.yaml), nothing breaks but quality signals are absent.

## First steps

```bash
# Open the latest broken pipeline in your browser:
echo "https://ci.pmon.dev/repos/schnappy/${labels_repo#schnappy/}/pipelines"
```

Or via API:

```bash
TOKEN=<your woodpecker user token>
curl -s -H "Authorization: Bearer $TOKEN" \
  "https://ci.pmon.dev/api/repos/$labels_repo/pipelines?status=failure&limit=3" \
  | python3 -m json.tool
```

## Common causes

| Symptom | Cause |
|---|---|
| ansible-lint failure | rule violation in a playbook |
| Gradle test failure | broken unit test or new dependency conflict |
| Kaniko build failure | base image pull issue, Dockerfile syntax, or registry credentials |
| SonarQube quality gate | code coverage / smell threshold breached |
| Dep-check failure | high CVE in a dependency that just published — review NVD |
| Network timeout | Forgejo / Nexus / git.pmon.dev briefly unreachable from build pod |

## Verify resolved

Push a fix → next build succeeds:

```bash
kubectl -n schnappy-infra exec prometheus-schnappy-prometheus-0 -c prometheus -- \
  wget -qO- "http://localhost:9090/api/v1/query?query=woodpecker_pipeline_count{repo=\"$REPO\"}"
```
shows `status=success` count incrementing without a new `status=failure` increment.

The alert auto-clears once the 5-min `increase()` window no longer contains a failure (i.e., 5+ min after the fix lands).
