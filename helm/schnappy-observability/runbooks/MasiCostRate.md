# MasiCostRate

**Severity:** critical · **For:** 10m

## What fired

`sum(rate(masi_llm_cost_usd_total[1h])) * 3600` is above `masiService.alerts.costRateUsdPerHour`.

## Impact

Money is leaving faster than planned. The daily cap still bounds it, so the worst case is one day's budget.

## First steps

`<ns>` is `schnappy-production` or `schnappy-test`; the deployment is `<ns>-masi` (browser: `<ns>-masi-browser`); the database is `masi` on the CNPG primary (`kubectl -n <ns> get cluster` names it).

```bash
kubectl -n <ns> exec deploy/<ns>-masi -c masi -- true   # pod is up?
# spend by purpose today (UTC), from the ledger the gauge is computed from
kubectl -n <ns> exec <ns>-postgres-1 -c postgres -- psql -d masi -c "select purpose, model, count(*), sum(coalesce(cost_usd, estimated_cost_usd)) usd from llm_call where created_at >= date_trunc('day', now() at time zone 'utc') group by 1,2 order by usd desc"
# the last hour, newest first
kubectl -n <ns> exec <ns>-postgres-1 -c postgres -- psql -d masi -c "select created_at, purpose, model, source_id, package_id, status, cost_usd from llm_call where created_at > now() - interval '1 hour' order by 1 desc limit 40"
```

## Common causes

| Symptom | Cause |
|---|---|
| One `package_id` repeats | a regenerate loop: guard failure → retry → failure; attempts should stop at 3 |
| One `source_id` repeats | an LLM-extract source on a short cron |
| Cost per call far above the estimate | pricing table wrong for the model, see MasiModelMismatch |

## Fix

- Stop the bleeding first: `masiService.tuning.auto: false` and disable the source; if it keeps rising, revoke the key at `<prefix>/ai-masi` (masi's own key: nothing else uses it).

## Verification

The rate falls below the threshold within the hour window.
