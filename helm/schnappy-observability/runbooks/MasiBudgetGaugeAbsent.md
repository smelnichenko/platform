# MasiBudgetGaugeAbsent

**Severity:** warning · **For:** 30m

## What fired

masi is `up` but publishes no `masi_llm_budget_used_ratio`. The budget alerts are computed by the app, so without the gauge they cannot fire.

## Impact

Spend is still capped inside masi (the cap is checked in the ledger transaction, not from the metric). What is lost is the warning before the cap.

## First steps

`<ns>` is `schnappy-production` or `schnappy-test`; the deployment is `<ns>-masi` (browser: `<ns>-masi-browser`).

```bash
kubectl -n <ns> logs deploy/<ns>-masi -c masi --since=1h | grep -iE 'budget|ledger|gauge'
kubectl -n <ns> exec deploy/<ns>-masi -c masi -- wget -qO- localhost:8080/api/masi/actuator/prometheus | grep masi_llm_budget
```

## Common causes

| Symptom | Cause |
|---|---|
| Gauge present in the pod, absent in Prometheus | scrape path or relabeling; check the ServiceMonitor target |
| Gauge absent in the pod | `AI_ENABLED=false` (no gateway bean) — then the alert is noise: check `masiService.ai.enabled` |
| Gauge is NaN | the ledger query fails: database unreachable, see MasiLedgerFailures |

## Fix

- Fix the scrape or the database; if AI is deliberately off in this namespace, the rule should not render there (`alerts.enabled`).

## Verification

`masi_llm_budget_used_ratio` has two series (day, month) for the namespace.
