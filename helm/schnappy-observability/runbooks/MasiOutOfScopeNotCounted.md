# MasiOutOfScopeNotCounted

**Severity:** warning · **For:** 15m

## What fired

No masi pod has counted its rows not connected to Estonia for over an hour. Each pod counts every sweep interval (ten
minutes) and publishes `masi_out_of_scope_rows` with the time of its last successful count,
`masi_out_of_scope_counted_timestamp_seconds`. A failed count leaves both unchanged; without this alert a count that fails
every time would keep showing its last 0, and MasiOutOfScopeRows could never fire.

## Impact

The out-of-scope sweep is blind: postings not connected to Estonia stored before the gate are not closed, and nothing
says whether any are there.

## First steps

```bash
kubectl -n <ns> logs deploy/<ns>-masi -c masi --since=2h | grep "out-of-scope rows were not counted"
```

## Fix

Fix whatever the WARN line names (the database unreachable, a timeout, a schema change). The next successful count sets
both values.

## Verification

`time() - max(masi_out_of_scope_counted_timestamp_seconds)` under 600 again.
