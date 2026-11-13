# MasiAddressesUnplaced

**Severity:** warning · **For:** 2d

## What fired

`max by (country) (masi_official_addresses_unplaced)` has been above 0 for two days: that many of the country's current
official addresses name, in their text, no place masi holds (their municipality, or their settlement or district inside
it). masi stores no place with an official address: it is found when the address is read, among the places held then,
by the address text's parts (component 2 the municipality, component 3 the settlement or district when the municipality
has one of that name). The gauge is counted again whenever the places or the addresses change, and at least daily.
Visibility only: nothing is stopped.

## Impact

An unplaced address still resolves at house level (its point and text), but without a place: a search by place misses
it, and a register address matching it carries no settlement or municipality.

## First steps

```bash
kubectl -n <ns> logs deploy/<ns>-masi -c masi --since=48h | grep 'name no place held now'   # the first ten, by text
kubectl -n <ns> exec <ns>-postgres-1 -c postgres -- psql -d masi -c "select started_at, status, left(error, 300) from source_run r join source s on s.id = r.source_id where s.key in ('places:ee', 'addresses:ee') order by 1 desc limit 6"
kubectl -n <ns> exec <ns>-postgres-1 -c postgres -- psql -d masi -c "select name, level, retired_on, updated_at from place where country = 'EE' and level = 'MUNICIPALITY' order by updated_at desc limit 10"
```

## Common causes

| Symptom | Cause |
|---|---|
| The texts name a municipality or village masi does not hold, and `places:ee` last ran before the Board's change | a reform the places have not brought yet: `places:ee` late, failing or switched off |
| `places:ee` ran after the change and the names still differ | EHAK and the address file disagree on a name (a rename one of them has not made) |
| Many addresses at once, all parts shifted | the address file's shape changed (a component added or dropped) |

## Fix

- Places behind: Run now on `places:ee` (Sources page). The count follows on its next tick (10 minutes), no address run
  needed - the order of the two sources does not matter.
- Names disagree: wait for the Board's next monthly files, or raise it with the Board.
- A new shape: masi's reader (`EstoniaAddressFile`, `EstoniaAddressJoin`) needs a change.

## Verification

The gauge back at 0 after the places' run (or the files' next month).
