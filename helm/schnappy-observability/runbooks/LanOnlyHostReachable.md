# LanOnlyHostReachable

**Severity:** critical · **For:** 5m

## What fired

The blackbox exporter (a pod, so outside `gatewayLanOnly.allowedCidrs`) requested
`$labels.instance` through the gateway and did **not** get 403, or the probe stopped reporting.

## Impact

`alerts`, `prometheus`, `hubble`, `reports` and `runbooks.pmon.dev` have no login. The router
forwards public :443 to the gateway and the Host header is the caller's choice, so without the
policy anyone on the internet can create Alertmanager silences, query Prometheus, or read Hubble
flows. A 200 here means the host is open; a 404/5xx/timeout means the gateway or route is broken.

## First steps

```bash
kubectl -n schnappy-infra get authorizationpolicy schnappy-infra-gateway-lan-only -o yaml
kubectl -n schnappy-infra get svc schnappy-infra-gateway-istio -o jsonpath='{.spec.externalTrafficPolicy}'
curl -s -o /dev/null -w '%{http_code}\n' https://alerts.pmon.dev/-/ready   # from the LAN: expect 200
```

## Common causes

| Symptom | Cause |
|---|---|
| Probe gets 200 | policy missing (mesh values/app pruned it) or its selector no longer matches the gateway pods |
| Probe gets 200, policy present | client IPs SNATed: `externalTrafficPolicy` not `Local` (gateway-patch Job did not run), or gateway pods on a node that does not own 192.168.11.2 |
| Probe gets 404 | route for that host removed — drop the URL from `prometheus.lanOnlyProbeUrls` |
| No series (`absent`) | blackbox exporter down or the Probe CR is gone |

## Fix

- Re-sync `schnappy-infra-mesh` (policy + gateway-patch Job). Never force-sync or prune root.
- Until fixed, the fastest containment is deleting the HTTPRoute of the exposed host.

## Verification

- `probe_success{job="blackbox-lan-only"}` is 1 for every instance; alert clears within 5m.
- From the LAN the host still answers 200.
