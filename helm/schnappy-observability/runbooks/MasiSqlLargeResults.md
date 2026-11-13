# MasiSqlLargeResults

**Severity:** warning · **For:** at once; clears an hour after the last one

## What fired

masi read a query result with more rows than its limit (1,000 unless the code that asked says, with
`ResultSizes.expect`, that it reads more on purpose and why). `masi_sql_large_results_total{caller}` names the masi method
that asked. The alert clears an hour after the last one.

## Impact

A list or a sweep reading a growing table whole: memory per request or per tick that grows with the data, and a query that
gets slower every week. One such read (every contact picture with its bytes) ran production out of memory (2026-11-11).

**A read serving an HTTP request is stopped there** (masi plan 118, PR 248): the request answers 500 ("This request
would read too many rows; it was stopped") - the page that asked shows an error, and the 5xx alert fires beside this one.
Background work (a collector, a sweep, a scheduled report) is only counted and said, as before.

## First steps

`<ns>` is `schnappy-production` or `schnappy-test`; the deployment is `<ns>-masi`.

```bash
# the warning names the SQL and the caller, once an hour per statement
kubectl -n <ns> logs deploy/<ns>-masi -c masi --since=2h | grep 'a result of more than'
# a request stopped by it: every time, with the SQL and the caller
kubectl -n <ns> logs deploy/<ns>-masi -c masi --since=2h | grep "a request's read stopped"
```

## Common causes

| Symptom | Cause |
|---|---|
| A list endpoint (a request answered 500) | a query without a page: give it a page through `Paging` (1..200 rows), or a `Limit`, and its endpoint `@BoundedList` when it answers a whole list |
| A scheduled sweep or backfill | a whole-table read: read it a page at a time after the last key (`KeysetPages`) |
| A reference table read whole on purpose | the read is right but undeclared: wrap it in `ResultSizes.expect(rows, why, ...)` |

## Fix

- Page the query, or declare the deliberate read - in masi's code, through a PR (the tests fail on a large result, so a
  test reproducing the read shows the fix works).

## Verification

After the fix is deployed, the alert clears within the hour and the warning no longer appears in the log.
