# MasiPlacesNotChecked

**Severity:** warning · **For:** 1h

## What fired

`time() - max by (country) (masi_places_checked_timestamp_seconds) > 35 days`: the country's places have not been
checked against their source for over 35 days. The timestamp is written by every apply - the seed at a fresh start
and each run of the country's source (`places:<country>`, monthly; `places:ee` on the 12th) - and read by each pod
every 10 minutes.

## Impact

The places go stale: new settlements, renames and boundary changes of the last month are missing. Nothing breaks at
once - the places held still serve.

## First steps

```bash
kubectl -n <ns> exec <ns>-postgres-1 -c postgres -- psql -d masi -c "select key, enabled, cron, health from source where key like 'places:%'"
kubectl -n <ns> exec <ns>-postgres-1 -c postgres -- psql -d masi -c "select started_at, status, complete, left(error, 300) from source_run r join source s on s.id = r.source_id where s.key = 'places:ee' order by 1 desc limit 5"
kubectl -n <ns> exec <ns>-postgres-1 -c postgres -- psql -d masi -c "select key, value from app_flag where key like 'places.checked.%'"
```

## Common causes

| Symptom | Cause |
|---|---|
| The source is disabled | it is seeded off: switch it on in the Sources page |
| Its runs fail | the feed changed (a file renamed, a zip without its `.dbf`/`.shp`/`.prj`, shapes not in EPSG 3301) - the run's error names it |
| Runs fail with a refused host | the environment's allow-list lacks `s3.pilw.io` / `geoportaal.maaruum.ee` / `download.geonames.org` (see platform `docs/masi-allowed-hosts.md`) |
| Runs fail reading the address file (`addressesUrl`: not found, cut, "joins no address to a settlement", "gives no postal code") | the Land Board's `sihtnumbrid.zip` moved, changed its shape, or was unreachable - the run applies nothing (EHAK's changes wait too); fix the URL or the reader, or remove `addressesUrl` from the config to read GeoNames' codes meanwhile (that churns the postal history: codes it lacks become former) |
| No source row | a build before the row was seeded |

## Fix

- Fix the source's config or the feed reading, then Run now on the Sources page.

## Verification

The source's run is OK, and the gauge moves to the run's time within 10 minutes.
