# CertExpiringIn7Days

**Severity:** critical · **For:** 30m

## What fired

cert-manager Certificate `$labels.namespace/$labels.name` has < 7 days until expiry. Renewal should have happened by now and didn't.

## Impact

Imminent. Once the cert expires, every TLS handshake to that hostname fails — services behind it are effectively down for any client validating certs.

## First steps

```bash
kubectl -n $NS get certificate $NAME -o yaml | yq '.status'
kubectl -n $NS get certificaterequests,orders,challenges 2>&1 | head
kubectl -n cert-manager logs deploy/cert-manager --tail=80 | grep -iE "$NAME|error" | tail -20
```

## Common causes

| Symptom | Cause |
|---|---|
| `Order` stuck `pending` | DNS-01 webhook (Porkbun) failing — check porkbun-webhook pod, API key in `secret/schnappy/porkbun` |
| `Challenge` `presentError` | DNS not propagating, or external resolver caching old `_acme-challenge` TXT |
| `CertificateRequest` `denied` | ClusterIssuer not Ready or rate-limit hit |
| `Certificate` `Ready: False` for hours | usually upstream — Let's Encrypt rate limit (5 dups/week per FQDN) |

## Manual rotation (last resort)

```bash
kubectl -n $NS delete certificate $NAME       # cert-manager recreates
kubectl -n $NS delete secret <tls-secret>     # forces fresh issuance
```

## Verify resolved

`kubectl get cert -A | grep $NAME` shows `READY=True` with `AGE` < 1h.
