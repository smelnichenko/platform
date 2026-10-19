# MasiSweepStarved

**Severity:** warning · **For:** 10m

## What fired

`masi_sweep_skipped_total{reason="lock_wait"}` grew by ten or more in two hours. The sweep that closes listings past
their own deadline runs every ten minutes, one transaction per job; it waits for a job's row no longer than the lock
wait (`masi.scheduler.lock-wait`, 5 s) and, when another writer still holds it, leaves that job to the next sweep and
counts it. One job held through every sweep of two hours counts twelve: a row held far longer than any write takes.
(`reason="ingest_busy"` is the count of the global ingest lock masi had before; an old image may still report it.)

## Impact

Listings whose deadline has passed stay open on the held job(s), and so do those jobs: they show as open, they can get
packages prepared (LLM spend), and the "open jobs" figures are too high. Nothing is lost — the sweep that gets the row
closes them, dated then.

## First steps

`<ns>` is `schnappy-production` or `schnappy-test`; the deployment is `<ns>-masi`; the database is `masi` on the CNPG primary.

```bash
# who holds what, and for how long (a long or idle-in-transaction session on job / company rows)
kubectl -n <ns> exec <ns>-postgres-1 -c postgres -- psql -d masi -c "select pid, state, now() - xact_start as in_tx, wait_event_type, left(query, 120) from pg_stat_activity where datname = 'masi' and xact_start is not null order by xact_start"
kubectl -n <ns> exec <ns>-postgres-1 -c postgres -- psql -d masi -c "select l.pid, l.mode, l.granted, c.relname from pg_locks l join pg_class c on c.oid = l.relation where c.relname in ('job', 'job_listing', 'company') order by l.granted, l.pid"
# runs still going, and what is waiting to be closed
kubectl -n <ns> exec <ns>-postgres-1 -c postgres -- psql -d masi -c "select s.key, r.started_at, now() - r.started_at as running from source_run r join source s on s.id = r.source_id where r.finished_at is null order by 2"
kubectl -n <ns> exec <ns>-postgres-1 -c postgres -- psql -d masi -c "select count(*) from job_listing where closed_at is null and expires_at < now() - interval '24 hours'"
```

## Common causes

| Symptom | Cause |
|---|---|
| A session `idle in transaction` for minutes | a writer that took a row lock and stopped: a stuck request or pod; its transaction holds the row until it ends |
| A long `ariregister` run repointing a company's jobs | the register import merging a stub into its company holds that company's job rows while it moves them |
| The same job held sweep after sweep, nothing idle | a writer that keeps re-taking the row (a retry loop) - find it in the masi log around the sweeps |

## Fix

- A stuck session: end it (`select pg_terminate_backend(<pid>)` - a write on the database: with the operator's OK) or
  restart the masi pod that owns it; its transaction rolls back and the next sweep closes the listings.
- A long import: nothing to do; the count stops when it ends.

## Verification

The log shows `closed N listing(s) past their deadline` and the counter stops growing.
