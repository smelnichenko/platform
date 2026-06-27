# VersitygwGatewayDown

**Severity:** warning · **For:** 5m

## What fired

A per-Pi blackbox probe of `http://<pi>:9000/health` failed — at least one of the two **versitygw** backup-store gateways is not serving. versitygw is stateless and runs on **both** Pis (pi1 `.4`, pi2 `.6`); the keepalived VIP `.5:9000` routes to a healthy one. One gateway down = lost redundancy; **both** down = the backup store (velero, etcd-backup, CNPG barman, ScyllaDB Manager) is unavailable. (This replaced `MinioDualActive` — with versitygw, dual-active is the *desired* state, not a fault.)

## Impact

One down: degraded — the VIP still serves from the survivor, backups keep working. Both down: backups and restores fail until a gateway returns.

## First steps

```bash
# which Pi's gateway is down?
for ip in 192.168.11.4 192.168.11.6; do
  echo "$ip: $(curl -s -o /dev/null -w '%{http_code}' --max-time 3 http://$ip:9000/health)"
done
# on the Pis (direct ssh is closed — go via ansible):
cd ~/src/ops/deploy/ansible
venv/bin/ansible -i inventory/production.yml pis -m shell \
  -a 'echo "$(hostname) versitygw=$(systemctl is-active versitygw)"; journalctl -u versitygw -n 20 --no-pager' --become
```

## Common causes

| Symptom | Cause |
|---|---|
| `versitygw inactive` / unit failed | crash — `journalctl -u versitygw`; `systemctl restart versitygw` |
| `/var/lib/minio/data` not mounted | versitygw's `RequiresMountsFor` blocks it from serving an empty dir — fix the Gluster mount first |
| Both down + Gluster quorum lost | a pi↔pi partition with `ten` (arbiter) unreachable → Gluster read-only; restore connectivity to `ten` |
| Probe fails but `curl` works | blackbox egress / NetworkPolicy to the Pi `.4/.6:9000` |

## Verify resolved

Both `http://192.168.11.4:9000/health` and `192.168.11.6:9000/health` return 200, the VIP `192.168.11.5:9000/health` returns 200, and the alert clears after 5m.
