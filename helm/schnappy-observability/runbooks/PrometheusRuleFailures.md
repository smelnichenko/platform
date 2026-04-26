# PrometheusRuleFailures

**Severity:** warning · **For:** 10m

## What fired

Prometheus has been failing to evaluate one or more rules — `increase(prometheus_rule_evaluation_failures_total[10m]) > 0`.

## Impact

Affected alerting rules may not fire when they should. Recording rules don't produce their derived series. Dashboards depending on those series go blank.

## First steps

```bash
kubectl -n schnappy-infra exec prometheus-schnappy-prometheus-0 -c prometheus -- \
  wget -qO- 'http://localhost:9090/api/v1/rules' | python3 -m json.tool | grep -B2 -A4 'health":"err'
kubectl -n schnappy-infra logs prometheus-schnappy-prometheus-0 -c prometheus --tail=80 | grep -iE 'rule.*err|invalid expr' | tail -10
```

## Common causes

| Symptom | Cause |
|---|---|
| `parse error` in PromQL | a recently edited rule has bad syntax — revert and fix |
| `invalid expression` referring to a label | renamed/removed metric — adjust the query or remove the rule |
| `vector matching` errors | series cardinality changed — drop unused labels with `sum without (...)` |
| All rules in one group failing | the file rendered wrong — `kubectl -n schnappy-infra get prometheusrule -o yaml \| yq '.spec.groups[].rules[].expr'` and re-render the chart |

## Common fixes

```bash
# After fixing the rule in the chart and pushing:
kubectl -n schnappy-infra exec prometheus-schnappy-prometheus-0 -c prometheus -- \
  wget -qO- --post-data='' http://localhost:9090/-/reload
```

## Verify resolved

`api/v1/rules` shows all rules `health: ok`.
