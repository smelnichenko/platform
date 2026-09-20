# MasiSweepStarved

**Severity:** warning · **For:** 10m

## What fired

`masi_sweep_skipped_total{reason="ingest_busy"}` grew by ten or more in two hours. The sweep that closes listings past
their own deadline runs every ten minutes and takes the same lock as the ingest of a collector run (one lock guards
every write of listing and job state). It waits five seconds for it and, when an ingest still holds it, leaves the work
to the next sweep. Skipped once is by design; ten of twelve means it practically never runs.

## Impact

Listings whose deadline has passed stay open, and with them their jobs: they show as open, they can get packages
prepared (LLM spend), and the "open jobs" figures are too high. Nothing is lost — the next sweep that gets the lock
closes them all, dated then.

## First steps

`<ns>` is `schnappy-production` or `schnappy-test`; the deployment is `<ns>-masi`; the database is `masi` on the CNPG primary.

```bash
# which run is ingesting, and for how long
kubectl -n <ns> exec <ns>-postgres-1 -c postgres -- psql -d masi -c "select s.key, r.started_at, now() - r.started_at as running, r.fetched, r.parsed from source_run r join source s on s.id = r.source_id where r.finished_at is null order by 2"
# what is waiting to be closed
kubectl -n <ns> exec <ns>-postgres-1 -c postgres -- psql -d masi -c "select count(*) from job_listing where closed_at is null and expires_at < now() - interval '24 hours'"
kubectl -n <ns> logs deploy/<ns>-masi -c masi --since=3h | grep -E "an ingest is writing|closed .* past their deadline"
```

## Common causes

| Symptom | Cause |
|---|---|
| One long-running `ariregister` run | the register import resolves tens of thousands of companies, one transaction each, under the lock; it runs weekly and takes a while |
| Many sources on the same cron minute | their ingests queue on the lock back to back |
| A run that never finishes | a wedged ingest: the run row has no `finished_at` and the pod's thread dump shows it inside `RegistryService.ingest` |

## Fix

- A long import: nothing to do, the alert clears when it ends. If it fires every week, move the register's cron to the night.
- Crons on one minute: spread them in the Sources page.
- A wedged ingest: restart masi (`kubectl -n <ns> rollout restart deploy/<ns>-masi`); the recovery sweep marks the run INTERRUPTED.

## Verification

The log shows `closed N listing(s) past their deadline` and the counter stops growing.
