# ExternalSecretSyncFailing

**Severity:** warning · **For:** 15m

## What fired

ExternalSecret `$labels.namespace/$labels.name` has been hitting non-zero `externalsecret_sync_calls_error` rate for 15+ min. ESO can't fetch from the secret store.

## Impact

The downstream k8s Secret is **not refreshing**. Existing values keep working until pod restart; once a consumer restarts and the rotated secret was needed (and never landed), it'll fail auth.

## First steps

```bash
kubectl -n $NS get externalsecret $NAME -o jsonpath='{.status.conditions}{"\n"}'
kubectl -n $NS describe externalsecret $NAME | tail -20
kubectl -n external-secrets logs deploy/external-secrets --tail=80 | grep -iE "$NAME|error" | tail -20
```

## Common causes

| Symptom | Cause |
|---|---|
| `Vault path not found` | seed-vault-secrets hasn't run, or path was deleted |
| `permission denied` | Vault token expired / policy missing path |
| `secret store not Ready` | upstream — see ClusterSecretStoreNotReady runbook |
| `property not found` | Vault path exists but missing the field — check seed-vault-secrets entry |
| Empty value in cluster Secret | Vault has empty value (silent missing env in seed playbook — check the assert hardening list) |

## Common fixes

```bash
# Force immediate sync
kubectl -n $NS annotate externalsecret $NAME force-sync=$(date +%s) --overwrite

# Re-seed and re-sync
cd /home/sm/src/ops && task deploy:seed-secrets
kubectl -n $NS annotate externalsecret $NAME force-sync=$(date +%s) --overwrite
```

## Verify resolved

`kubectl get externalsecret -A | grep $NAME` shows `STATUS=SecretSynced READY=True`.
