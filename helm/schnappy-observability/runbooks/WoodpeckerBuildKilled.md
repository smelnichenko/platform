# WoodpeckerBuildKilled

**Severity:** warning

## What fired

A run of **main** on `$labels.repo` (`$labels.workflow`: an app repo's `cd`, or the `ci` of platform, infra or ops) was
killed 30-40 min ago, and no pipeline of that repo has ended since. Woodpecker marks a run killed when it hits the repo's
timeout, when its agent restarts under it (SIGTERM), or when someone cancels it by hand. A kill by cancel-previous - the
next push's pipeline replacing it - is not this: the replacement ends within the half hour and the alert stays quiet.

The metrics: `woodpecker_step_failures_total` counts the killed step (30-40 min ago, `type!="service"`), and
`woodpecker_pipeline_count` - which counts only pipelines that ENDED, success or failure - did not rise for the repo in
the 40 min since. A count series born in those 40 min counts as a pipeline ended too: a branch's first pipeline, or the
first after a Woodpecker restart (`increase()` reads a series' first sample as no rise). WoodpeckerBuildFailed does not
fire for a kill (a killed pipeline is no failure).

The step counter names no branch. In platform, infra and ops, which run `ci` on every branch push, a branch's run killed
and never replaced reads as main's: look at the killed pipeline's branch before restarting it. A red branch, whose
pipeline ends as a failure, does not fire this.

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
| the killed pipeline is a branch's (platform, infra, ops) | a branch run cancelled or timed out; the counter cannot tell it from main's - restart it, or delete the branch if it is done |

## Resolve

Restart the pipeline (the UI's restart button, or push the fix). The alert clears 40 min after the kill, or as soon as
any pipeline of the repo ends.
