# MasiSourceDisabledAuto

**Severity:** warning · **For:** 5m

## What fired

`masi_source_health == 3` (`DISABLED_AUTO`): the source failed ten runs in a row and masi stopped scheduling it.

## Impact

That board is no longer collected. Its listings are **not** closed (only a complete, successful run counts misses), so the registry goes stale rather than wrong.

## First steps

`<ns>` is `schnappy-production` or `schnappy-test`; the deployment is `<ns>-masi` (browser: `<ns>-masi-browser`); the database is `masi` on the CNPG primary (`kubectl -n <ns> get cluster` names it).

```bash
# the run ledger says why, in the source's own words
kubectl -n <ns> exec <ns>-postgres-1 -c postgres -- psql -d masi -c "select r.started_at, r.status, r.complete, r.fetched, r.parsed, left(r.error, 200) from source_run r join source s on s.id = r.source_id where s.key = '<source>' order by 1 desc limit 10"
kubectl -n <ns> logs deploy/<ns>-masi -c masi --since=6h | grep 'source=<source>' | tail -40
```

## Common causes

| Symptom | Cause |
|---|---|
| `markup changed` / `no job anchors` | the site changed its HTML or API: the collector and its fixture need updating |
| `is not on masi.http.allowed-hosts` | see MasiSourceHostNotAllowed |
| 403 / 429 | the board blocks or rate-limits us: lengthen the cron, check `terms_note` |
| TIMEOUT every run | pacing (`minIntervalMs`) times pages exceeds the deadline |

## Fix

- Fix the cause, then re-enable in the Sources page (that resets the failure counter). Never re-enable a source that is blocked by the site's terms.

## Verification

The next run is `OK` and `masi_source_health` returns to 0.
