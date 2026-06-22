# KeycloakReconcileStale

## What

The admin service's periodic admin→Keycloak role reconcile has not completed
successfully for over 3 hours (`admin_keycloak_reconcile_last_success` not
advancing), or has never succeeded since the pod started. It normally runs
hourly, re-applying every user's effective permissions to Keycloak and
self-healing any drift left by a live sync that failed silently.

## Impact

The **drift safety-net is down**. Any role/offboarding change whose live sync
failed (see `KeycloakSyncFailing`) will NOT be corrected until the reconcile
runs again — so a revoked permission could stay live in Keycloak indefinitely.

## Diagnose

1. Is the admin pod up and Ready?
   `kubectl get pods -n <ns> -l app.kubernetes.io/component=admin`.
2. `kubectl logs -n <ns> deploy/<release>-admin -c admin | grep -i 'Keycloak reconcile'`
   — "reconcile run failed" is a loop-level error (e.g. DB unavailable); no log
   at all means the scheduler isn't running or KC isn't configured.
3. `admin_keycloak_reconcile_runs_total{result="failure"}` rising → the loop is
   erroring; the log line has the cause.
4. The reconcile bean is `@ConditionalOnBean(RealmResource.class)` — if KC admin
   isn't wired at all, the metric is absent (a different problem).

## Fix

- Admin down → restore it; the reconcile runs ~2 min after start, then hourly.
- Loop erroring on a dependency (DB/KC) → fix it; the next scheduled run clears
  the alert once `admin_keycloak_reconcile_last_success` advances.
