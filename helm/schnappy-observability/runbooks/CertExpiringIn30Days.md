# CertExpiringIn30Days

**Severity:** warning · **For:** 1h

## What fired

cert-manager Certificate `$labels.namespace/$labels.name` has < 30 days until `notAfter`.

## Impact

None yet — purely a heads-up. Same `Certificate` resource has its own renewal cycle (cert-manager attempts renewal at 2/3 lifetime); this alert tells us renewal hasn't happened *yet*.

## First steps

```bash
kubectl -n $NS get certificate $NAME -o yaml | grep -A2 'status:'
kubectl -n $NS describe certificate $NAME | tail -20
kubectl -n $NS get challenges,orders 2>&1 | head
```

## Common causes

| Symptom | Cause |
|---|---|
| Renewal scheduled in future, not started | normal — wait until cert-manager triggers (1/3 of lifetime remaining) |
| Status `Ready: False` | renewal attempted and failed → see CertManagerRenewalFailing runbook |
| No renewal logged | issuer ref broken, ClusterIssuer not Ready |
| HTTP-01 / DNS-01 challenge stuck | check `kubectl get challenges -A` for pending state |

## When to act

If `CertExpiringIn7Days` (critical) follows, the renewal mechanism has actually failed. Until then, monitor only.

## Verify resolved

`kubectl get cert -A | grep $NAME` shows `READY=True` with a fresh `AGE` (renewal happened).
