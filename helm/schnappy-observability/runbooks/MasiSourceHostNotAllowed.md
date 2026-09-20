# MasiSourceHostNotAllowed

**Severity:** warning · **For:** 15m

## What fired

`masi_source_refused_hosts > 0`: the source's **last run** tried that many distinct hosts that
`masiService.http.allowedHosts` does not list. It counts what the run actually tried, wherever the
URL came from: the source row, a default inside the collector (an API base), a job link on a list
page, a redirect. A browser source counts the hosts the page itself was on or was sent to — not
trackers or fonts a page loads, whose refusal is the guard doing its job.

## Impact

masi contacts **only** listed hosts, by exact name. Every fetch to the unlisted host is refused
before DNS: the source fails, or reads its list without the job pages behind it (descriptions
missing), or reports itself incomplete — and an incomplete run closes nothing.

## First steps

`<ns>` is `schnappy-production` or `schnappy-test`; the deployment is `<ns>-masi`; the database is `masi` on the CNPG primary (`kubectl -n <ns> get cluster` names it).

```bash
# the hosts, by name: the runner logs them after every such run
kubectl -n <ns> logs deploy/<ns>-masi -c masi --since=6h | grep 'not on masi.http.allowed-hosts'
# the same, from the run ledger
kubectl -n <ns> exec <ns>-postgres-1 -c postgres -- psql -d masi -c "select started_at, status, complete, left(error, 300) from source_run r join source s on s.id = r.source_id where s.key = '<source>' order by 1 desc limit 5"
# what the pod was given
kubectl -n <ns> get deploy <ns>-masi -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="MASI_HTTP_ALLOWED_HOSTS")].value}' | tr ',' '\n'
```

## Common causes

| Symptom | Cause |
|---|---|
| A new or edited source | its host was never added to the chart list |
| A host the row does not mention | the collector's own default (e.g. `api.smartrecruiters.com`), or the job pages live on another host than the list (`<tenant>.teamdash.com`) |
| Every source at once | the list is empty: the env var did not render, and an empty list allows nobody, by design |
| `www.` vs bare name | names are exact; there is no wildcard and no suffix match |

## Fix

- If the host is one masi should read: add the exact name to `masiService.http.allowedHosts` (platform values) and let Argo roll masi.
- If not: correct or disable the source. Do not widen the list to make an alert go away.

## Verification

The source's next run logs no refusal and the gauge is 0 (it is set at the end of every run; "Run now" in the Sources page does not wait for the cron).
