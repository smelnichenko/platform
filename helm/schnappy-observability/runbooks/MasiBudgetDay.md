# MasiBudgetDay

**Severity:** warning · **For:** 5m

## What fired

`masi_llm_budget_used_ratio{period="day"}` is above 0.8: masi has spent more than 80 % of `masiService.ai.dailyBudgetUsd` since 00:00 UTC.

## Impact

None yet. At 100 % the gateway stops sending requests: packages stay `NEW`, LLM-extract runs end `SKIPPED_BUDGET`. Nothing errors and nothing is lost; work resumes at 00:00 UTC.

## First steps

`<ns>` is `schnappy-production` or `schnappy-test`; the deployment is `<ns>-masi` (browser: `<ns>-masi-browser`); the database is `masi` on the CNPG primary (`kubectl -n <ns> get cluster` names it).

```bash
kubectl -n <ns> exec deploy/<ns>-masi -c masi -- true   # pod is up?
# spend by purpose today (UTC), from the ledger the gauge is computed from
kubectl -n <ns> exec <ns>-postgres-1 -c postgres -- psql -d masi -c "select purpose, model, count(*), sum(coalesce(cost_usd, estimated_cost_usd)) usd from llm_call where created_at >= date_trunc('day', now() at time zone 'utc') group by 1,2 order by usd desc"
```

## Common causes

| Symptom | Cause |
|---|---|
| Many `TUNE` rows | a backlog re-tune (`POST /packages/retune`) or `tuning.auto` on with a burst of new jobs |
| Many `EXTRACT` rows for one `source_id` | an LLM-extract source looping over a large page; check its per-run cap |
| Rows stuck `PENDING`/`LOST` | restarts mid-call: the estimate stays reserved until the day rolls over |

## Fix

- Expected spend: nothing to do, or raise `masiService.ai.dailyBudgetUsd` in infra values.
- Unexpected: set `masiService.tuning.auto: false`, or disable the source in the Sources page. The key's spend limit in the Anthropic console is the backstop.

## Verification

The ratio stops rising; the dashboard's "LLM cost today" equals the query above.
