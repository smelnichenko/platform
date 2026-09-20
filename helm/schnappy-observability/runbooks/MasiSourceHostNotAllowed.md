# MasiSourceHostNotAllowed

**Severity:** warning · **For:** 15m

## What fired

`masi_source_refused_hosts > 0`: a scheduled source's own row (base URL or a URL in its config) names a host that `masiService.http.allowedHosts` does not list.

## Impact

masi contacts **only** listed hosts, by exact name. Every fetch to the unlisted host is refused before DNS, so the source fails or reads partially (and then reports itself incomplete).

## First steps

`<ns>` is `schnappy-production` or `schnappy-test`; the deployment is `<ns>-masi` (browser: `<ns>-masi-browser`).

```bash
kubectl -n <ns> logs deploy/<ns>-masi -c masi --since=2h | grep 'not on masi.http.allowed-hosts'
kubectl -n <ns> get deploy <ns>-masi -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="MASI_HTTP_ALLOWED_HOSTS")].value}' | tr ',' '\n'
```

## Common causes

| Symptom | Cause |
|---|---|
| A new or edited source | its host was never added to the chart list |
| List is empty | the env var did not render: an empty list allows nobody, by design |
| `www.` vs bare name | names are exact; there is no wildcard and no suffix match |

## Fix

- If the host is one masi should read: add the exact name to `masiService.http.allowedHosts` (platform values) and let Argo roll masi.
- If not: correct or disable the source row. Do not widen the list to make an alert go away.

## Verification

The log line stops after the next refresh (60 s) and the gauge is 0.
