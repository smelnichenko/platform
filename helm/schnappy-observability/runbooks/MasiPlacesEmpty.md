# MasiPlacesEmpty

**Severity:** critical · **For:** 15m

## What fired

`max by (country) (masi_places) == 0`: no masi pod counts a single current place for that country. Each pod counts the
country's current places (`place` rows, not retired, the country's own row aside) from the database every 10 minutes;
the largest count across pods is taken, so one pod that has not counted yet does not fire it.

## Impact

The places are what the scope gate and place search read: with none, postings and people cannot be placed in the
country, and place search answers nothing. Places are never deleted (a trigger refuses it), so none current means the
table was emptied by hand, every row retired, or a fresh database whose seed did not run.

## First steps

`<ns>` is `schnappy-production` or `schnappy-test`; the database is `masi` on the CNPG primary.

```bash
kubectl -n <ns> exec <ns>-postgres-1 -c postgres -- psql -d masi -c "select country, kind <> 'COUNTRY' as place, retired_on is null as current, count(*) from place group by 1, 2, 3 order by 1, 2, 3"
kubectl -n <ns> logs deploy/<ns>-masi -c masi --since=2h | grep -E 'PlaceSeeder|places of'
```

## Common causes

| Symptom | Cause |
|---|---|
| No rows at all for the country | a fresh database whose seed failed at start (masi's start fails then - see its log) |
| Rows, all retired | a run applied a feed that held none of them (a broken read): see the source's last run |
| Rows, current, gauge 0 | the count fails: `places of <country> not counted` in the log |

## Fix

- Retired by a broken read: run the country's source again (`places:<country>`, Sources page, Run now) once the feed is
  whole; a place back in the feed is current again.
- A fresh database: restart masi - the seed applies the snapshot when the country holds no current place.

## Verification

`masi_places{country="<country>"}` is the feed's count (Estonia 4,812, 2026-11) on every pod within 10 minutes.
