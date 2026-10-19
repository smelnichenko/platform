# MasiJobClosedWithOpenListing

**Severity:** warning · **For:** 30m

## What fired

`masi_jobs_closed_with_open_listing` has been above 0 for half an hour: a job is CLOSED while one of its listings is
still open. A job closes only when none of its listings is open, under the job's row lock; nothing repairs this state
(the recovery repairs only the reverse, an OPEN job with no open listing), so 0 is the only right value. Every pod
publishes the same count (it is read from the database each sweep interval).

## Impact

The job shows as closed although a board still shows it: it is missing from open jobs, reports and matching, and no
package is prepared for it.

## First steps

```bash
kubectl -n <ns> exec <ns>-postgres-1 -c postgres -- psql -d masi -c "select j.id, j.title, j.closed_at, l.id as listing, l.source_id, l.last_seen_at from job j join job_listing l on l.job_id = j.id where j.status = 'CLOSED' and l.closed_at is null order by j.closed_at desc limit 20"
# the writers around that time (a close and an opener of the same job on two pods)
kubectl -n <ns> logs deploy/<ns>-masi -c masi --since=2h | grep -E "closed|reopen|merged"
```

## Fix

Reopen the job so it matches its listings (a write on the database: with the operator's OK):

```sql
update job set status = 'OPEN', closed_at = null where status = 'CLOSED'
  and exists (select 1 from job_listing l where l.job_id = job.id and l.closed_at is null);
```

Then find how it happened: it means a writer closed a job or opened a listing without the job's row lock - a defect in
masi to fix, with a test that forces the two writers.

## Verification

The gauge reads 0 at the next sweep interval.
