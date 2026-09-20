# MasiBudgetMonth

**Severity:** critical · **For:** 5m

## What fired

`masi_llm_budget_used_ratio{period="month"}` is above 0.9 of `masiService.ai.monthlyBudgetUsd` (UTC month).

## Impact

At 100 % masi makes no LLM call until the 1st: no tuning, no posting analysis, no LLM extraction. Deterministic and browser collectors keep running.

## First steps

`<ns>` is `schnappy-production` or `schnappy-test`; the deployment is `<ns>-masi` (browser: `<ns>-masi-browser`); the database is `masi` on the CNPG primary (`kubectl -n <ns> get cluster` names it).

```bash
kubectl -n <ns> exec deploy/<ns>-masi -c masi -- true   # pod is up?
# spend by purpose this month (UTC), from the ledger the gauge is computed from
kubectl -n <ns> exec <ns>-postgres-1 -c postgres -- psql -d masi -c "select purpose, model, count(*), sum(coalesce(cost_usd, estimated_cost_usd)) usd from llm_call where created_at >= date_trunc('month', now() at time zone 'utc') group by 1,2 order by usd desc"
```

## Common causes

| Symptom | Cause |
|---|---|
| Steady daily spend near the daily cap | the daily cap times 30 exceeds the monthly cap: the two were sized apart |
| One day dominates | see MasiBudgetDay / MasiCostRate for that day |

## Fix

- Decide: raise `monthlyBudgetUsd`, or let it stop. Turn `tuning.auto` off to keep the remainder for manual "Prepare".

## Verification

Ratio flat; after the 1st (UTC) it returns to 0.
