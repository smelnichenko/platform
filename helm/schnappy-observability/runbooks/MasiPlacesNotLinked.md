# MasiPlacesNotLinked

**Severity:** warning · **For:** 5m

## What fired

`masi_places_link_failed{country} == 1` on a pod: at its start, linking the country's places into the hierarchy (each
place's level, parent and path) failed. masi started anyway; the attempt's transaction rolled back, so the places keep the
links they had. The pod's log says why.

## Impact

Searches by place level ("anywhere in Harju maakond") read the links: they work as before the start, but anything the
start meant to link (places applied before the hierarchy existed) stays unlinked until a start or a run links it.

## First steps

```bash
kubectl -n <ns> logs deploy/<ns>-masi -c masi --since=2h | grep 'could not be linked'
kubectl -n <ns> exec <ns>-postgres-1 -c postgres -- psql -d masi -c "select kind, count(*) from place where country = '<country>' and level is null group by 1"
```

## Common causes

| Symptom | Cause |
|---|---|
| "of kinds NUTS1, NUTS2, NUTS3 have no level" | an image older than the EU frame (masi 27bdc3f) after `places:eu` has run: a rollback below it |
| another kind named | a feed wrote a kind no build knows yet - a code defect |

## Fix

- A rollback: roll forward to an image that knows the kinds.
- A new kind: map it in `PlaceKinds.LEVEL_OF_KIND` with its feed, ship, the next start links it.

## Verification

The gauge is 0 on every pod after the next start, and the log's "linked into the hierarchy" line, if any, names the country.
