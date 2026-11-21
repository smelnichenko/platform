# WoodpeckerBuildFailed

**Severity:** warning

## What fired

A pipeline that builds **main** failed on `$labels.repo`: a step of it failed within the last 10 min (30 min for the `ci` of platform, infra and ops, where a short step fails beside a 15-minute one and its pipeline ends long after) while the repo's count of FAILED pipelines rose. The workflow is the `cd` of an app repo (it runs only on a push to main), the nightly cron workflows `depcheck` (monitor: OWASP dependency-check of every app) and `pitest` (each app's mutation tests), or the `ci` workflow of platform, infra or ops (they push to main directly; their pull requests run `ci` too and fire it). `$labels.workflow` names which. The metrics are `woodpecker_step_failures_total{workflow, type!="service"}` (which workflow) and `woodpecker_pipeline_count{status="failure"}` (that the pipeline ended as failure). A failed pull-request pipeline of an app repo does not fire it: that is feedback for its author, on the PR (`woodpecker_pipeline_count` alone cannot tell - a pull request's pipeline is labelled with its target branch, so every PR counts as `main`). A KILLED pipeline does not fire it either: cancel-previous kills a pipeline when the next push lands, and Woodpecker never counts a killed pipeline as failed - a kill nothing replaced is WoodpeckerBuildKilled's.

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
| Dep-check failure (`depcheck`, nightly) | high CVE in a dependency that just published — review NVD |
| `pitest` failure (nightly) | mutation score under the app's threshold, or a test that only fails under PIT — its report is in the step log |
| Network timeout | Forgejo / Nexus / git.pmon.dev briefly unreachable from build pod |

## Verify resolved

Push a fix → next build succeeds:

```bash
kubectl -n schnappy-infra exec prometheus-schnappy-prometheus-0 -c prometheus -- \
  wget -qO- "http://localhost:9090/api/v1/query?query=woodpecker_pipeline_count{repo=\"$REPO\"}"
```
shows `status=success` count incrementing without a new `status=failure` increment.

The alert clears once its windows no longer hold the failure: 10 min after the failed pipeline ended (the step side holds 10 min, 30 min for the GitOps repos' `ci`).
