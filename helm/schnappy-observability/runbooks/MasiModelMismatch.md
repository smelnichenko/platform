# MasiModelMismatch

**Severity:** warning · **For:** 0m

## What fired

The API answered with a model id other than the configured one (`configured` → `returned` labels). masi prices a call by the configured model.

## Impact

The ledger may be pricing calls with the wrong table, so the budget ratios are off in an unknown direction.

## First steps

`<ns>` is `schnappy-production` or `schnappy-test`; the deployment is `<ns>-masi` (browser: `<ns>-masi-browser`); the database is `masi` on the CNPG primary (`kubectl -n <ns> get cluster` names it).

```bash
kubectl -n <ns> exec <ns>-postgres-1 -c postgres -- psql -d masi -c "select model, count(*), sum(cost_usd) from llm_call where created_at > now() - interval '1 day' group by 1"
```

## Common causes

| Symptom | Cause |
|---|---|
| `returned` is a dated snapshot of `configured` | an alias resolved to a snapshot: pricing is the same, add the id to the pricing table |
| `returned` is another family | the configured model was retired or redirected |

## Fix

- Set `masiService.ai.tuningModel` / `extractModel` to the id the API returns and add its prices under `masi.ai.pricing`.

## Verification

No new increments of `masi_llm_model_mismatch_total`.
