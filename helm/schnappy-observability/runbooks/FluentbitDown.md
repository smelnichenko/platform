# FluentbitDown

**Severity:** warning · **For:** 10m

## What fired

A `schnappy-fluentbit-*` DaemonSet pod hasn't been Ready for 10+ min on at least one node.

## Impact

Logs from pods on the affected node are **not shipped to ClickHouse**. Already-tailed buffer survives a brief pod restart, but a pod stuck in CrashLoop loses any logs accumulated past the WAL.

## First steps

```bash
kubectl -n schnappy-infra get pod -l app.kubernetes.io/component=fluentbit
kubectl -n schnappy-infra describe pod $POD | tail -30
kubectl -n schnappy-infra logs $POD -c fluent-bit --tail=80 | grep -iE 'error|fail|warn' | tail -10
kubectl -n schnappy-infra get pod schnappy-clickhouse-0 -o jsonpath='{.status.phase}{"\n"}'
```

## Common causes

| Symptom | Cause |
|---|---|
| Container OOMKilled | log volume burst — bump `fluentbit.resources.limits.memory` (default 512Mi) |
| ConfigMap drift | recent fluent-bit chart change — check checksum/config annotation |
| ClickHouse 404 (`Table logs.podlogs does not exist`) | post-install init Job didn't run / silent-failed — see ClickHouse-init Job |
| ClickHouse 400 timestamp parse | URL missing `&date_time_input_format=best_effort` |
| All pods Ready but no logs in CH | RBAC issue on fluent-bit's k8s metadata enrichment — check ClusterRoleBinding |

## Verify resolved

```bash
kubectl -n schnappy-infra exec schnappy-clickhouse-0 -c clickhouse -- \
  clickhouse-client --query "SELECT count() FROM logs.podlogs WHERE timestamp > now() - INTERVAL 1 MINUTE"
```
returns a non-zero count.
