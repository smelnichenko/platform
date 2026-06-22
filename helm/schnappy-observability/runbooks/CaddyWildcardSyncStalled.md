# CaddyWildcardSyncStalled

## What

The `*.pmon.dev` wildcard cert served by **Caddy on the Pis** (probed via
`auth.pmon.dev`) is within 25 days of expiry. A healthy system keeps it >28
days out: cert-manager renews the wildcard ~30 days before expiry, and the
per-Pi `caddy-wildcard-sync.timer` pulls the new cert from the cluster within a
day and restarts Caddy. Crossing 25 days means that propagation has stalled.

## Impact

Not down yet — this is the early-warning. If left, the served cert keeps
counting down: `PublicSSLCertExpiringSoon` follows at <14d, and once it expires
every HTTPS handshake to the Pi-served hosts (git / auth / nexus / s3.pmon.dev)
fails. This alert exists to pre-empt exactly that outage, which happened once.

## Diagnose

1. **Is cert-manager renewing?** `kubectl get certificate pmon-dev-wildcard-tls -n schnappy-infra`
   — check the renewal time / not-after. If `CertManagerRenewalFailing` is also
   firing, the problem is upstream (DNS-01 / ACME), not the Pi sync.
2. **Is the Pi sync timer healthy?**
   `ssh pi1 systemctl status caddy-wildcard-sync.timer caddy-wildcard-sync.service`
   and `ssh pi1 journalctl -u caddy-wildcard-sync` — look for curl / token /
   RBAC errors (a failed run leaves the oneshot service `failed`).
3. **Compare issued vs served:**
   `kubectl get secret pmon-dev-wildcard-tls -n schnappy-infra -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -noout -enddate`
   vs `echo | openssl s_client -connect auth.pmon.dev:443 2>/dev/null | openssl x509 -noout -enddate`.
   A gap confirms the serving layer hasn't picked up the renewal.

## Fix

- **Quickest** — re-run the deploy, which re-pulls the cert immediately and
  also refreshes the SA token: `cd ops && task deploy:caddy`.
- **Or** trigger the sync job on each Pi directly:
  `ssh pi1 sudo systemctl start caddy-wildcard-sync.service` (and `pi2`).

## Why this can happen

The Pis serve a **file** cert (per-host ACME is broken for `.dev`), so they
depend on this pull. The reader SA token is non-expiring and scoped to GET only
this one (publicly-served) Secret; the apiserver endpoint is baked into the
sync script at deploy time, so a control-plane re-IP also requires a
`task deploy:caddy`.
