# ScyllaManagerDown

**Severity:** warning · **For:** 15m

## What fired

Prometheus has not scraped Scylla Manager for 15 minutes (`absent(up{job="scylla-manager", namespace="scylla-manager"} == 1)`): Manager down, its ServiceMonitor gone, or the scrape dropped.

## How bad

Backups and repairs may still run, but nothing watches them: the other Scylla alerts are blind.

## First steps

```bash
M="kubectl -n scylla-manager exec deploy/scylla-manager -c scylla-manager --"
$M sctool cluster list
$M sctool tasks -c <cluster from the alert>
$M sctool progress -c <cluster> <type>/<task name>      # the last run: its error per host
kubectl -n scylla-manager logs deploy/scylla-manager --since=6h | grep -iE 'error|fail' | tail -20
```

## Root-cause investigation

| Symptom | Cause |
|---|---|
| `agent not available`, `connection refused` to a node's 10001 | the ScyllaDB pod's manager agent down or not yet registered (after a pod restart) |
| `AccessDenied`, `NoSuchBucket` in a backup | the agents' store credentials (`scylla-agent-config-secret`) or the `scylla-backups` bucket |
| `context deadline exceeded` uploading | the Pi backup store slow or down |
| the task missing from `sctool tasks` | the operator did not register it: its ScyllaDBManagerTask resource (`kubectl get scylladbmanagertasks -A`) and the operator's log |

## Fix

`kubectl -n scylla-manager get pods,servicemonitor`; Prometheus' targets page for `serviceMonitor/scylla-manager/scylla-manager/0` (its last error: a timeout means schnappy-infra's default-deny lost its scylla-manager egress rule).

## Verification

The target is up; the alert resolves.
