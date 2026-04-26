# CertManagerRenewalFailing

**Severity:** critical · **For:** 1h

## What fired

A `Certificate` has been in `Ready=False` for 1h+. cert-manager tried to issue or renew, and failed.

## Impact

Future TLS handshakes will fail once the existing cert (if any) expires. If this is a fresh issuance, the consumer Service has no usable cert at all — public URL down.

## First steps

```bash
kubectl get cert -A | grep -v "True"
kubectl -n $NS describe cert $NAME | tail -30
kubectl -n $NS get orders,challenges,certificaterequests
kubectl -n cert-manager logs deploy/cert-manager --tail=100 | grep -iE "$NAME|error|warn" | tail -20
```

## Common causes

| Symptom | Cause |
|---|---|
| Order `pending` for hours | DNS-01 challenge failing — Porkbun webhook down or API key stale |
| Challenge `presentError` "no such record" | Porkbun API returned success but TXT not propagating to Let's Encrypt |
| `acme: rate limit` | hit weekly cap (5 duplicate certs per FQDN per week) |
| ClusterIssuer `Ready: False` | wrong ACME account key, broken HTTP-01 solver, or webhook reference mismatch |
| RBAC error in cert-manager logs | missing role binding for the issuer's solver |

## Common fixes

```bash
# Force a fresh order
kubectl -n $NS delete certificaterequest -l cert-manager.io/certificate-name=$NAME

# Restart cert-manager to flush stuck reconciles
kubectl -n cert-manager rollout restart deploy cert-manager

# Verify Porkbun webhook
kubectl -n cert-manager logs deploy/porkbun-webhook --tail=20
```

## Verify resolved

`kubectl get cert -A | grep $NAME` shows `READY=True`.
