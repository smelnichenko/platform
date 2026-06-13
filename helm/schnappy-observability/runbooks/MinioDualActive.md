# MinioDualActive

**Severity:** critical · **For:** 3m

## What fired

More than one Pi is serving MinIO (`/minio/health/live` returns 200 on both
192.168.11.4 and 192.168.11.6). MinIO runs `xl-single` on the **shared**
Gluster volume `backup-minio`, so two live servers write the same data dir
concurrently — which can corrupt xl-single metadata. Exactly one Pi (the
`minio/active` Consul-lock holder) should ever serve.

## Why it should be impossible

MinIO's systemd unit wraps `ExecStart` in `consul lock minio/active` (Plan
072). Only the quorum lock holder runs MinIO; a second start blocks on the
lock, and a minority-partition node loses the lock and is killed. If this
alert fires, that fence has failed.

## Triage

1. Which Pi holds the VIP: `ssh ten 'for h in pi1 pi2; do ssh $h "ip -o addr show to 192.168.11.5/32"; done'` — MinIO should run only there.
2. Who holds the lock: `ssh pi1 'consul kv get -detailed minio/active/.lock'` — one session, or none.
3. Per-Pi MinIO: `for h in pi1 pi2; do ssh $h 'systemctl is-active minio; curl -s -o /dev/null -w "%{http_code}\n" localhost:9000/minio/health/live'; done`.
4. Consul health: `ssh ten 'curl -s 192.168.11.4:8500/v1/status/peers'` — quorum must include `ten`.

## Mitigate

- Stop MinIO on the **non-VIP-holder** immediately: `ssh <non-holder> 'sudo systemctl stop minio'`, then run `/etc/keepalived/converge.sh` there.
- If Consul lost quorum (the fence can't enforce), restore it before restarting MinIO anywhere.
- Confirm single-active afterward: only the VIP holder serves and holds `minio/active`.

## Likely causes

- Consul quorum loss (lock can't be enforced) — check `ten` reachability.
- A manual `systemctl start minio` on the non-holder that didn't go through keepalived (the fence still blocks it, but verify).
- The unit reverted to a non-`consul lock` `ExecStart` (check `systemctl cat minio`).
