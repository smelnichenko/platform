# PublicEndpointSlow

**Severity:** warning · **For:** 10m

## What fired

End-to-end blackbox probe to `$labels.instance` took > 3 seconds for 10+ min. The endpoint *responds*, but slowly.

## Impact

User-visible. All traffic to that hostname feels sluggish. Mobile / lossy connections may experience timeouts even though the probe technically succeeds.

## First steps

```bash
curl -w '\ntime: dns=%{time_namelookup} conn=%{time_connect} tls=%{time_appconnect} ttfb=%{time_starttransfer} total=%{time_total}\n' -s -o /dev/null https://$INSTANCE/

# Where's the time going?
kubectl -n schnappy-infra exec prometheus-schnappy-prometheus-0 -c prometheus -- \
  wget -qO- "http://localhost:9090/api/v1/query?query=probe_http_duration_seconds{instance=\"$INSTANCE\"}" | python3 -m json.tool
```

## Common causes

| Symptom | Cause |
|---|---|
| `tls=` is the slowest phase | cert handshake renegotiation or OCSP stapling delay |
| `ttfb=` is huge | upstream service is slow (DB query, cold-start, GC pause) |
| `dns=` slow | CoreDNS overloaded — `kubectl -n kube-system top pod -l k8s-app=kube-dns` |
| `conn=` slow | Cilium/L2 backend issues, or Istio sidecar warmup |
| Recurring at top of minute | scheduled job (Velero backup, cron) saturating the host |

## Verify resolved

`probe_duration_seconds{job="blackbox-public",instance="$INSTANCE"} < 3` for 10 min.
