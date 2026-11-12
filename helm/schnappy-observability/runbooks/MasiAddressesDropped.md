# MasiAddressesDropped

**Severity:** warning · **For:** 15m

## What fired

`max by (country) (masi_official_addresses{state="current"})` is under 0.95 of its highest in the day before: over a
twentieth of the country's current official addresses were retired at once. A run of `addresses:<country>` retires
every address its file - read whole and checked - no longer holds. Visibility only: nothing stopped the run.

## Impact

Retired addresses stay in the table (never deleted) but are no longer current: an address resolved to one keeps its link,
new resolutions do not find it. If the file was short by mistake, the next complete run brings them back.

## First steps

```bash
kubectl -n <ns> exec <ns>-postgres-1 -c postgres -- psql -d masi -c "select started_at, status, left(error, 500) from source_run r join source s on s.id = r.source_id where s.key = 'addresses:ee' order by 1 desc limit 3"
kubectl -n <ns> exec <ns>-postgres-1 -c postgres -- psql -d masi -c "select retired_on, count(*) from official_address where country = 'EE' and retired_on is not null group by 1 order by 1 desc limit 5"
kubectl -n <ns> exec <ns>-postgres-1 -c postgres -- psql -d masi -c "select split_part(full_text, ', ', 2) municipality, count(*) from official_address where country = 'EE' and retired_on = (select max(retired_on) from official_address where country = 'EE') group by 1 order by 2 desc limit 10"
```

## Common causes

| Symptom | Cause |
|---|---|
| The run's note names many retired ADR_IDs across the country | the Board's file was short (a partial export): check the file's size and row count against last month's |
| The retired addresses are in one or a few municipalities | a real reform (a merger, a renumbering): the register's change - nothing to fix |

## Fix

- A short file: Run now once the Board has published a whole one - the addresses come back as current ("back in the
  file" in the run's note).
- A reform: nothing; the alert resolves a day after the fall.

## Verification

After a whole file's run the gauge is back near its earlier count, or the fall is understood as the register's own.
