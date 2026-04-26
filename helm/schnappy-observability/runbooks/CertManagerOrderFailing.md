# CertManagerOrderFailing

**Severity:** warning · **For:** 30m

## What fired

cert-manager has been hitting 4xx/5xx from the ACME server (Let's Encrypt) — > 5 errors in the last 30min.

## Impact

New certificate orders won't complete. Existing certs continue to work until expiry; if this persists past renewal time, expect `CertExpiringIn7Days` next.

## First steps

```bash
kubectl get orders,challenges -A | grep -v "valid\|True"
kubectl -n cert-manager logs deploy/cert-manager --tail=100 | grep -iE 'rate|error|429' | tail -20
kubectl -n cert-manager logs deploy/porkbun-webhook --tail=50 | tail -20
```

## Common causes

| Symptom | Cause |
|---|---|
| `429 Too Many Requests` | Let's Encrypt rate limit hit — wait or use staging |
| Webhook pod down | porkbun-webhook crashing / no API creds |
| 5xx from ACME server | Let's Encrypt outage — check status.letsencrypt.org |
| 4xx with "DNS problem" | TXT record not propagating, Porkbun API failing to publish |

## Verify resolved

`increase(certmanager_http_acme_client_request_count{status=~"4..|5.."}[30m])` returns 0; in-flight Orders move to `valid`.
