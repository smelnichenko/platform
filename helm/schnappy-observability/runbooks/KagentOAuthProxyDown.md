# KagentOAuthProxyDown

**Severity:** warning · **For:** 10m

## What fired

The `kagent-oauth2-proxy` Deployment has 0 available replicas for 10+ min (namespace `kagent`).

## Impact

oauth2-proxy is the **only** public entry to the console: `kagent.pmon.dev` routes to it,
and it runs the Keycloak OIDC login before proxying to the UI. While it's down the
console is unreachable (login fails). The controller/agents keep running — not a
cluster-wide issue.

## First steps

```bash
kubectl -n kagent get deploy kagent-oauth2-proxy
kubectl -n kagent logs deploy/kagent-oauth2-proxy --tail=80
kubectl -n kagent get es/kagent-oauth2-proxy secret/kagent-oauth2-proxy
curl -sI https://kagent.pmon.dev/oauth2/start 2>&1 | head
```

## Common causes

| Symptom in logs | Cause |
|---|---|
| `missing setting: client-id/client-secret/cookie-secret` | the `kagent-oauth2-proxy` ESO Secret didn't sync — Vault `secret/schnappy/kagent-oauth` not seeded, or an ESO error |
| `cookie_secret must be 16, 24, or 32 bytes` | the seeded `cookie_secret` is the wrong length |
| `oidc: issuer did not match` / discovery timeout | Keycloak `kagent-ui` client missing, or `auth.pmon.dev` unreachable (egress) |
| `redirect_uri ... is not allowed` | the Keycloak client redirect ≠ `https://kagent.pmon.dev/oauth2/callback` |

## Fix

- Secret missing → seed Vault `secret/schnappy/kagent-oauth` (`client_id`/`client_secret`/`cookie_secret`) via `seed-vault-secrets.yml`; confirm `kubectl -n kagent get es kagent-oauth2-proxy` is `SecretSynced`.
- Keycloak → verify the `kagent-ui` confidential client and its redirect URI in the schnappy realm.
- Then `kubectl -n kagent rollout restart deploy/kagent-oauth2-proxy`.

## Verification

- `curl -sI https://kagent.pmon.dev/oauth2/start` → `302` to Keycloak
- Browser login at `kagent.pmon.dev` redirects to Keycloak and back to the console
