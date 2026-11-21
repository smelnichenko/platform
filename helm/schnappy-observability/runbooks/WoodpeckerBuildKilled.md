# WoodpeckerBuildKilled

**Severity:** warning

## What fired

A run of **main** on `$labels.repo` (`$labels.workflow`: an app repo's `cd`, or the `ci` of platform, infra or ops) was
killed 30-40 min ago, and no pipeline of that repo has ended since. Woodpecker marks a run killed when it hits the repo's
timeout, when its agent restarts under it (SIGTERM), or when someone cancels it by hand. A kill by cancel-previous - the
next push's pipeline replacing it - is not this: the replacement ends within the half hour and the alert stays quiet.

The metrics: `woodpecker_step_failures_total` counts the killed step (30-40 min ago, `type!="service"`), and
`woodpecker_pipeline_count` - which counts only pipelines that ENDED, success or failure - did not rise for the repo in
the 40 min since. WoodpeckerBuildFailed does not fire for a kill (a killed pipeline is no failure).

## Impact

The killed run's commit was never built or deployed: for `cd`, production and test stay on the previous image; for the
GitOps repos' `ci`, the commit's checks never ran. Nothing retries on its own.

## First steps

```bash
# the repo's latest pipelines: the killed one shows status "killed"
echo "https://ci.pmon.dev/repos/schnappy/${labels_repo#schnappy/}/pipelines"
```

Or via API (ops `.env` holds `WOODPECKER_API_TOKEN`):

```bash
curl -s -H "Authorization: Bearer $TOKEN" "https://ci.pmon.dev/api/repos/<id>/pipelines?status=killed&limit=3" | python3 -m json.tool
```

## Common causes

| Symptom | Cause |
|---|---|
| a step ran until the repo's timeout | a hung test or a step waiting on a service that never came up (masi cd 525) |
| killed while every step looked healthy | the Woodpecker agent restarted (a node reboot, an upgrade) |
| killed with no other pipeline after it | cancelled by hand, or the push after it had no workflows ([CI SKIP], docs only) and so replaced nothing |

## Resolve

Restart the pipeline (the UI's restart button, or push the fix). The alert clears 40 min after the kill, or as soon as
any pipeline of the repo ends.
