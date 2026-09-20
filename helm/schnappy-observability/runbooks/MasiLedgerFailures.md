# MasiLedgerFailures

**Severity:** critical · **For:** 0m

## What fired

`masi_llm_ledger_failures_total` increased: masi made (or was about to make) an LLM call and could not write its `llm_call` row.

## Impact

A call whose row is missing is spend the budget does not see. The reserve step runs before the request, so most failures mean no request was sent; a failure in the settle step means a real cost recorded only as its estimate.

## First steps

`<ns>` is `schnappy-production` or `schnappy-test`; the deployment is `<ns>-masi` (browser: `<ns>-masi-browser`); the database is `masi` on the CNPG primary (`kubectl -n <ns> get cluster` names it).

```bash
kubectl -n <ns> logs deploy/<ns>-masi -c masi --since=30m | grep -iE 'ledger|llm_call'
kubectl -n <ns> exec <ns>-postgres-1 -c postgres -- psql -d masi -c "select status, count(*) from llm_call where created_at > now() - interval '1 day' group by 1"
```

## Common causes

| Symptom | Cause |
|---|---|
| Connection errors | Postgres or PgBouncer down or failing over |
| `PENDING` rows piling up | settle failing; the sweeper turns them `LOST` after 10 min and keeps the estimate |

## Fix

- Restore the database path. No manual ledger edits: `LOST` rows are the honest record.

## Verification

The counter stops increasing; new rows reach `OK`.
