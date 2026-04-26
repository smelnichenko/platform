# PublicSSLCertExpiringSoon

**Severity:** warning · **For:** 1h

## What fired

The TLS certificate currently served at `$labels.instance` expires in < 14 days. Detected via blackbox probe's `probe_ssl_earliest_cert_expiry` metric.

## Impact

None yet. Becomes critical near 0 (browser warnings, automated client failures).

This is a different signal than `CertExpiringIn30Days` / `CertExpiringIn7Days` — those check cert-manager's `Certificate` objects (renewal lifecycle in the cluster). This one checks the cert **actually being served on the wire** through Caddy / the Pi gateway / Istio. Mismatches between the two flag deployment problems (cert renewed but not picked up by serving layer).

## First steps

```bash
echo | openssl s_client -connect $INSTANCE:443 -servername $HOST 2>/dev/null | openssl x509 -noout -issuer -subject -dates
kubectl -n $NS get cert | grep $HOST
```

If `kubectl get cert` shows fresh `AGE` but the served cert is stale → the proxy didn't pick up the new cert. For Istio: `kubectl -n istio-system rollout restart deploy istiod`. For Caddy on Pi: `ssh pi1 sudo systemctl reload caddy`.

## Common causes

| Symptom | Cause |
|---|---|
| Fresh cert in cluster, old on wire | proxy needs reload |
| Cert is also stale in cluster | renewal failing — see CertManagerRenewalFailing |
| Domain not managed by cert-manager | manual / ACME-on-Pi cert — check `/etc/caddy/certs/` |

## Verify resolved

`(probe_ssl_earliest_cert_expiry{instance="$INSTANCE"} - time()) / 86400 > 30`.
