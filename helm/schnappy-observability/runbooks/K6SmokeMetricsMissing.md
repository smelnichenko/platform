# K6SmokeMetricsMissing

**Severity:** warning · **For:** 1h

## What fired

A k6 smoke hook Job completed in `$labels.namespace` within the last day, but
Mimir holds no `k6_checks_rate` sample for that namespace since. k6 pushes its
metrics to `schnappy-mimir.schnappy-infra:9009` at the end of every run and
**exits 0 when that push fails**, so the hook stays green and
`K6SmokeTestFailing` stays blind — this alert is the only signal for that.
(Gated on the Job via kube-state-metrics, so a month without a deploy does
not fire.)

## Impact

Smoke results are not being recorded: the k6 dashboard is stale and a failing
check would not alert. The smoke itself may still be passing.

## First steps

```bash
NS=<namespace>
kubectl -n $NS get job ${NS}-k6-smoke -o jsonpath='{.metadata.creationTimestamp}{"\n"}'
kubectl -n $NS logs job/${NS}-k6-smoke -c k6 | grep -E 'Failed to send|checks_succeeded'
```

Older runs: ClickHouse `logs.podlogs` (`container = 'k6'`).

| Finding | Cause |
|---|---|
| `Failed to send the time series … context deadline exceeded` | the push is not answered — most often dropped in the network: the namespace default-deny (infra `cluster-config/<ns>-default-deny.yaml`) must allow egress to the Mimir pods on 9009 (`gateway: "true"` + `component: mimir`); Hubble shows `POLICY_DENIED` for the k6 pod to port 9009. Also Mimir slow/overloaded |
| `Failed to send … connection refused` / 5xx | Mimir itself — `kubectl -n schnappy-infra get pods -l app.kubernetes.io/component=mimir`, its logs |
| push succeeded, Mimir has the series (`last_over_time(k6_checks_rate{namespace="<ns>"}[1d])` on the Mimir datasource) but Prometheus does not (`k6_checks_rate{namespace="<ns>", source="k6"}` empty on :9090) | the `source=k6` tag is missing from the k6 command (chart `k6-postsync-job.yaml`), or Prometheus' `remoteRead` from Mimir (infra `prometheus/values.yaml`, `requiredMatchers: source: k6`, `readRecent: true`) is missing or Mimir's `/prometheus/api/v1/read` is failing (`PrometheusRuleFailures` would fire too) |

## Verify resolved

After the next sync, on Prometheus (through the remote read):

```promql
last_over_time(k6_checks_rate{namespace="<ns>", source="k6"}[1d])
```

returns the checks at 1, and the k6 log has no `Failed to send` line.
