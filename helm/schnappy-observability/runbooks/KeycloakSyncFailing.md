# KeycloakSyncFailing

## What

The admin service failed to push a user's role or enabled-status change to
Keycloak in the last hour (`admin_keycloak_sync_failures_total` incremented, tag
`operation=roles|enabled`). These syncs run live on permission/offboarding
changes and were previously **log-only** — this alert makes them visible.

## Impact

A user's Keycloak roles (and thus their JWT permissions) may be **stale relative
to the admin DB**: a granted permission isn't active yet, or — more importantly
— a **revoked / offboarded** permission is still live in KC until corrected. The
hourly reconcile (`KeycloakReconcileService`) retries automatically, so a one-off
blip self-heals within the hour; a persistent alert means it isn't healing.

## Diagnose

1. `kubectl logs -n <ns> deploy/<release>-admin -c admin | grep -iE 'Failed to (sync|update) KC'`
   — the failing user UUID + the KC error.
2. The `operation` label (`roles` vs `enabled`) narrows which Admin API call failed.
3. Is the companion `KeycloakReconcileStale` alert also firing? If not, the
   hourly reconcile is still correcting drift.

## Fix

- Transient KC/network blip: the next reconcile fixes it — confirm
  `admin_keycloak_reconcile_last_success` is advancing.
- Persistent: fix KC Admin API access (client credentials, KC reachable, the
  role exists), then restart the admin pod (reconcile runs ~2 min after start)
  or wait for the hourly run.
