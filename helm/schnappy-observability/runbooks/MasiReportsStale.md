# MasiReportsStale

**Severity:** warning · **For:** 1h

## What fired

`masi_report_period_end_timestamp_seconds{kind="WEEKLY"}` is more than nine days old. The weekly report is written Monday 06:00 Europe/Tallinn and caught up on every restart.

## Impact

The Reports page shows no new week. Live stats (`/stats`) still work; only the stored snapshots are missing.

## First steps

`<ns>` is `schnappy-production` or `schnappy-test`; the deployment is `<ns>-masi` (browser: `<ns>-masi-browser`); the database is `masi` on the CNPG primary (`kubectl -n <ns> get cluster` names it).

```bash
kubectl -n <ns> logs deploy/<ns>-masi -c masi --since=48h | grep -iE 'report'
kubectl -n <ns> exec <ns>-postgres-1 -c postgres -- psql -d masi -c "select kind, period_start, period_end, generated_at from report order by period_end desc limit 5"
```

## Common causes

| Symptom | Cause |
|---|---|
| Exception in the log | a stats query fails on some row: the report for that period is never written, and catch-up retries it each time |
| No log lines at all | scheduling is off (`MASI_ENABLED=false`) or masi has been down across every cron and restart |

## Fix

- Fix the query or the data; then `POST /api/masi/reports/generate` for the missing period, or restart masi and let catch-up run.

## Verification

A new `report` row; the gauge moves to its `period_end`.
