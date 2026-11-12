# MasiAddressesNotChecked

**Severity:** warning · **For:** 1h

## What fired

`time() - max by (country) (masi_official_addresses_checked_timestamp_seconds) > 35 days`, and the timestamp is not 0:
the country's official address file has not been read whole for over 35 days, though it has been before. The timestamp
is written at the end of each complete run of the country's source (`addresses:<country>`, monthly; `addresses:ee` on
the 13th at 07:30, Tallinn) and read by each pod every 10 minutes. 0 means the source never completed a run - as while
it is seeded off - which is no alert.

## Impact

The official addresses go stale: new addresses, renumberings and new postcodes of the last month are missing; addresses
the register retired stay current. Nothing breaks at once - the addresses held still serve.

## First steps

```bash
kubectl -n <ns> exec <ns>-postgres-1 -c postgres -- psql -d masi -c "select key, enabled, cron, health from source where key like 'addresses:%'"
kubectl -n <ns> exec <ns>-postgres-1 -c postgres -- psql -d masi -c "select started_at, status, complete, left(error, 300) from source_run r join source s on s.id = r.source_id where s.key = 'addresses:ee' order by 1 desc limit 5"
kubectl -n <ns> exec <ns>-postgres-1 -c postgres -- psql -d masi -c "select key, value from app_flag where key like 'addresses.checked.%'"
```

## Common causes

| Symptom | Cause |
|---|---|
| The source was switched off | switch it on in the Sources page |
| Runs fail at a line of the file | the Board changed the file's shape (header, separator, charset, grid) - the run's error names the line; the reader refuses it rather than misread it |
| Runs fail "stopped at its deadline" | the run outgrew its `deadlineSeconds` (1800): raise it in the source's config, then Run now - what was written stays |
| Runs fail with a refused host | the environment's allow-list lacks `geoportaal.maaruum.ee` (see platform `docs/masi-allowed-hosts.md`) |
| Runs fail "holds no address" | the Board published an empty file: nothing was written or retired; Run now once the file is back |

## Fix

- Fix the source's config or the reader for the file's new shape, then Run now on the Sources page.

## Verification

The source's run is OK, and the gauge moves to the run's time within 10 minutes.
