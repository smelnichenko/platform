# MasiSqlLargeResults

**Severity:** warning · **For:** at once

## What fired

masi read a query result with more rows than its limit (1,000 unless the code that asked says, with
`ResultSizes.expect`, that it reads more on purpose and why). `masi_sql_large_results_total{caller}` names the masi method
that asked; the series stays until masi restarts.

## Impact

A list or a sweep reading a growing table whole: memory per request or per tick that grows with the data, and a query that
gets slower every week. One such read (every contact picture with its bytes) ran production out of memory (2026-11-11).

## First steps

`<ns>` is `schnappy-production` or `schnappy-test`; the deployment is `<ns>-masi`.

```bash
# the warning names the SQL and the caller, once an hour per statement
kubectl -n <ns> logs deploy/<ns>-masi -c masi --since=2h | grep 'a result of more than'
```

## Common causes

| Symptom | Cause |
|---|---|
| A list endpoint | a query without a page: give it `Limit`/`Pageable` with a server-side size clamp |
| A scheduled sweep or backfill | a whole-table read: read it a page at a time after the last key (`KeysetPages`) |
| A reference table read whole on purpose | the read is right but undeclared: wrap it in `ResultSizes.expect(rows, why, ...)` |

## Fix

- Page the query, or declare the deliberate read - in masi's code, through a PR (the tests fail on a large result, so a
  test reproducing the read shows the fix works).

## Verification

After the fix is deployed (masi restarts), the series is gone and the warning no longer appears in the log.
