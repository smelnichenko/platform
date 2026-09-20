# MasiSourceNotClosing

**Severity:** warning · **For:** 15m

## What fired

`masi_source_last_misses_counted_timestamp_seconds` is older than three of the source's own
intervals **while the source keeps succeeding** (a source that does not succeed at all is
`MasiSourceStale`). A run counts misses — the only way a vanished listing moves towards closing —
only when it was **complete** and **stored every listing it saw**.

## Impact

Nothing of that source closes. Jobs that were filled weeks ago stay `OPEN`, get packages prepared
(LLM spend) and inflate every "open jobs" figure. Nothing is lost or wrong in the other direction.

## First steps

`<ns>` is `schnappy-production` or `schnappy-test`; the database is `masi` on the CNPG primary.

```bash
kubectl -n <ns> exec <ns>-postgres-1 -c postgres -- psql -d masi -c "select r.started_at, r.status, r.complete, r.misses_counted, r.parsed, left(r.error, 300) from source_run r join source s on s.id = r.source_id where s.key = '<source>' order by 1 desc limit 10"
```

## Common causes

| Symptom | Cause |
|---|---|
| `complete = f`, error starts `run incomplete:` | the collector says why: a page cap or the deadline reached before the end of the list, an API that returned fewer than it counts, postings without an id, a card that had to be dropped |
| `complete = t`, error has `listing(s) not ingested (so no misses counted this run)` | one listing cannot be stored (the message names its URL and the database error): an over-long field, a colliding key |
| Error names a refused host | see MasiSourceHostNotAllowed: job pages that cannot be read can drop cards |

## Fix

- Incomplete by cap or deadline: raise the source's `maxPages` / `deadlineSeconds`, or narrow its filter, in the Sources page.
- A listing that cannot be stored: fix the mapping in the collector (bound the field); it is a bug, not data to delete.

## Verification

The next run has `misses_counted = t`; the gauge moves to its start time.
