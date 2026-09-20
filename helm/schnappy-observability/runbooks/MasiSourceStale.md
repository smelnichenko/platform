# MasiSourceStale

**Severity:** warning · **For:** 15m

## What fired

An enabled source has had no successful run for three of its own cron intervals (`masi_source_interval_seconds`). A source that never succeeded counts from the time it was enabled.

## Impact

Same as a disabled source, earlier: new postings from that board are not arriving.

## First steps

`<ns>` is `schnappy-production` or `schnappy-test`; the deployment is `<ns>-masi` (browser: `<ns>-masi-browser`); the database is `masi` on the CNPG primary (`kubectl -n <ns> get cluster` names it).

```bash
# the run ledger says why, in the source's own words
kubectl -n <ns> exec <ns>-postgres-1 -c postgres -- psql -d masi -c "select r.started_at, r.status, r.complete, r.fetched, r.parsed, left(r.error, 200) from source_run r join source s on s.id = r.source_id where s.key = '<source>' order by 1 desc limit 10"
kubectl -n <ns> logs deploy/<ns>-masi -c masi --since=6h | grep 'source=<source>' | tail -40
kubectl -n <ns> get pods -l app.kubernetes.io/component=masi
```

## Common causes

| Symptom | Cause |
|---|---|
| Runs exist and fail | see MasiSourceDisabledAuto for the causes |
| Runs are `SKIPPED_BROWSER` | the browser pod is unreachable: MasiBrowserUnreachable |
| Runs are `SKIPPED_BUDGET` | LLM budget exhausted: MasiBudgetDay / MasiBudgetMonth |
| No runs at all | masi was down, or the cron is invalid (logged at refresh) |

## Fix

- As the cause dictates. "Run now" in the Sources page proves the fix without waiting for the cron.

## Verification

`masi_source_last_success_timestamp_seconds` moves; the alert clears.
