# MasiDigestGivenUp

**Severity:** warning · **For:** 0m

## What fired

masi tried `masi.mail.max-attempts` (5) times to mail a weekly digest to one reader and gave up (`masi_report_notifications_total{outcome="given_up"}`). The passes run Monday 06:00 Europe/Tallinn, after a restart, and hourly at :30.

## Impact

The report itself is written and on the site (`/masi/reports`); only the mail is missing. That reader is not mailed about that week again. Other readers and later weeks are unaffected.

## First steps

`<ns>` is `schnappy-production` or `schnappy-test`; the deployment is `<ns>-masi`; the database is `masi` on the CNPG primary (`kubectl -n <ns> get cluster` names it).

```bash
kubectl -n <ns> exec <ns>-postgres-1 -c postgres -- psql -d masi -c "select n.report_id, r.period_start::date, n.user_uuid, n.attempts, n.sent_at, n.last_error from report_notification n join report r on r.id = n.report_id order by n.id desc limit 10"
kubectl -n <ns> logs deploy/<ns>-masi -c masi --since=8h | grep -i "weekly digest"
kubectl -n <ns> get externalsecret | grep mail
```

`last_error` is the exception type only, and readers are uuids: masi never stores or logs an address or a mail server's words (they quote the address).

## Common causes

| `last_error` | Cause |
|---|---|
| `MailAuthenticationException` | the SMTP password in Vault `<env>/mail` is wrong or was rotated at the provider |
| `MailSendException` with every reader failing | the provider is down, the sending domain lost its verification, or the pod cannot reach the SMTP port (NetworkPolicy: `masiService.mail.enabled` renders the 587 rule; Hubble shows the drop) |
| `MailSendException` for one reader only | that reader's address bounces at submission: fix it in Keycloak (admin re-emits `USER_CREATED`, masi updates its copy) |

## Fix

- Repair the cause, then give the digest its attempts back — it is sent on the next hourly pass, if the week ended less than `masi.mail.notify-within` (3 d) ago:

```sql
update report_notification set attempts = 0, last_error = null where sent_at is null and report_id = <id>;
```

- Older than that, the week is history: read it on the site.

## Verification

`sent_at` is set on the row, the log says "the weekly digest left for reader <uuid>", and `masi_report_notifications_total{outcome="sent"}` moved.
