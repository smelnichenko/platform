# MasiLlmAccountRefused

**Severity:** critical · **For:** 0m

## What fired

The Anthropic API refused masi's *account*, not a request: `reason` is `NO_CREDIT` (the credit balance is too low — the API answers this as a plain `400 invalid_request_error`), `KEY_REFUSED` (401, the key is unknown or revoked) or `NOT_PERMITTED` (403).

## Impact

Nothing is analysed, scored afresh or tuned. masi charges the refusal to nobody: packages stay `NEW` with their attempts, postings keep their analysis attempts, and both lanes pause for `masi.ai.account-pause` (1 h) before asking once more. Nothing is billed.

## First steps

`<ns>` is `schnappy-production` or `schnappy-test`; the deployment is `<ns>-masi`; the database is `masi` on the CNPG primary (`kubectl -n <ns> get cluster` names it).

```bash
kubectl -n <ns> exec <ns>-postgres-1 -c postgres -- psql -d masi -c "select created_at, purpose, model, error from llm_call where status = 'ERROR' order by id desc limit 10"
kubectl -n <ns> logs deploy/<ns>-masi -c masi --since=3h | grep -i "refused the account"
```

The ledger's `error` names the reason in masi's own words; the API's text is never stored (a 400 can quote the request, and the request holds a CV).

## Common causes

| Reason | Cause |
|---|---|
| `NO_CREDIT` | the Anthropic account behind the key has no credit left (Console → Plans & Billing) |
| `KEY_REFUSED` | the key in Vault `<env>/ai-masi` was revoked, rotated in the console only, or seeded wrong |
| `NOT_PERMITTED` | the key's workspace may not use the configured model |

## Fix

- `NO_CREDIT`: top up the account. No redeploy; the lanes try again within the hour.
- `KEY_REFUSED`: put the working key in `ops/.env` as `MASI_ANTHROPIC_API_KEY`, run `task deploy:seed-test-secrets` (or the production seed), wait for the ExternalSecret to sync and restart the masi deployment.
- `NOT_PERMITTED`: grant the model to the key's workspace, or set `masiService.ai.tuningModel` / `extractModel` to one it may use.

## Verification

No new increments of `masi_llm_account_refusals_total`; the next `llm_call` rows are `OK`; a `NEW` package becomes `PREPARED`.
