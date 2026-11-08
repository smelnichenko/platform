# MasiOutOfScopeRows

**Severity:** warning · **For:** 30m

## What fired

masi holds rows that are not connected to Estonia (plan 110: masi keeps only postings located in Estonia or remote
and open to it, and people whose own stated place names Estonia). Every ten minutes each masi pod closes the open
postings the scope gate would not store now, and counts:

- `kind="postings"`: open postings out of scope it could not close (another writer held the job, or a merge moved it);
- `kind="people"`: GitHub people whose profile names no Estonian place. A sweep never deletes people.

## Impact

People or postings with no tie to Estonia show in masi's lists, scores and reports, against the operator's rule.

## First steps

```bash
# postings: which open ones fail the rule (the sweep logs each it could not close)
kubectl -n <ns> logs deploy/<ns>-masi -c masi --since=1h | grep "not connected to Estonia"
# people: the GitHub contacts whose stated place names no Estonian one
kubectl -n <ns> exec <ns>-postgres-1 -c postgres -- psql -d masi -c "select c.id, c.github_login, c.profile_json::jsonb->>'location' from contact c join source s on s.id = c.source_id where s.key = 'github' and c.profile_json is not null and coalesce(c.profile_json::jsonb->>'location','') !~* 'estonia|eesti|tallinn|tartu|p[aä]rnu|narva' limit 50"
```

## Fix

- **Postings:** the next sweeps close them once the holding writer is done; one that stays means its job is held for
  good (see MasiIngestHeld) or the rule and the gate disagree - a bug in `EstoniaScope`.
- **People:** find how they came in (their source, the run that captured them) - a collector path that skips the gate is a
  bug. Deleting them is the operator's decision: show them the list and the delete command, and wait for their OK.

## Verification

`max by (kind) (masi_out_of_scope_rows)` back at 0 for both kinds.
