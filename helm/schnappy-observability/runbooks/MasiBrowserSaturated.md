# MasiBrowserSaturated

**Severity:** warning · **For:** 15m

## What fired

`masi_browser_sessions_active` has equalled `masiService.browser.maxParallel` for 15 minutes.

## Impact

Further browser runs wait for a permit and may hit their deadline (`TIMEOUT`).

## First steps

`<ns>` is `schnappy-production` or `schnappy-test`; the deployment is `<ns>-masi` (browser: `<ns>-masi-browser`); the database is `masi` on the CNPG primary (`kubectl -n <ns> get cluster` names it).

```bash
kubectl -n <ns> exec <ns>-postgres-1 -c postgres -- psql -d masi -c "select s.key, r.started_at from source_run r join source s on s.id = r.source_id where r.finished_at is null order by 2"
kubectl -n <ns> top pod -l app.kubernetes.io/component=masi-browser
```

## Common causes

| Symptom | Cause |
|---|---|
| The same sources every time | too many browser sources on the same cron minute: spread the crons |
| Sessions never end | a page that never goes network-idle; the run deadline closes it, check for `TIMEOUT` |
| Gauge stuck with no run in progress | a permit leaked: restart masi and report it as a bug |

## Fix

- Spread the crons first. Raising `maxParallel` needs browser memory to match (150–300 MiB per context).

## Verification

The gauge drops below the limit between runs.
