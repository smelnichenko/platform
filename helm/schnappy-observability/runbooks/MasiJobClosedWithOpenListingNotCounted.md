# MasiJobClosedWithOpenListingNotCounted

**Severity:** warning · **For:** 15m

## What fired

No masi pod has counted its CLOSED jobs with an open listing for over an hour. Each pod counts every sweep interval
(ten minutes) and publishes `masi_jobs_closed_with_open_listing` with the time of its last successful count,
`masi_jobs_closed_with_open_listing_counted_timestamp_seconds`. A failed count leaves both values unchanged. Without this
alert, a count that fails every time would keep showing its last 0, and MasiJobClosedWithOpenListing could never fire.

## Impact

Nothing in masi breaks. The check for jobs closed while a listing is open is blind until counting works again.

## First steps

```bash
# why the count fails (masi logs it at WARN on every failed attempt)
kubectl -n <ns> logs deploy/<ns>-masi -c masi --since=2h | grep "were not counted"
# the query's cost on the database: a timeout points to a plan gone bad or to locks
kubectl -n <ns> exec <ns>-postgres-1 -c postgres -- psql -d masi -c "select pid, state, wait_event_type, wait_event, now() - query_start as running, left(query, 120) from pg_stat_activity where datname = 'masi' and state <> 'idle' order by running desc"
```

## Fix

Fix whatever the WARN line names: the database unreachable, a query timeout, or a schema change. Nothing needs to be
reset. The next successful count sets both values.

## Verification

The timestamp moves again within ten minutes, and the alert clears.
