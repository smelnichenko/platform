# SmartctlExporterDown

**Severity:** warning · **For:** 10m

## What fired

`up{job="smartctl-exporter"} == 0` — Prometheus can't scrape the host-level smartctl_exporter on ten.

## Impact

All other Smartctl* alerts are silent until this resolves. Drive failures are no longer being detected.

## First steps

```bash
ssh ten 'systemctl status smartctl_exporter --no-pager | head -20'
ssh ten 'sudo journalctl -u smartctl_exporter --since "30 min ago" --no-pager | tail -30'
ssh ten 'curl -s http://192.168.11.2:9633/metrics | head -3'
ssh ten 'ss -lntp | grep 9633'
```

## Common causes

| Symptom | Cause |
|---|---|
| systemd unit failed | Check journalctl for stack trace; usually permission or `/dev/nvme*` access |
| Port not listening | Service not running — `systemctl restart smartctl_exporter` |
| Connection refused from cluster | nftables blocking 9633 from CNI CIDR — check `nft list ruleset` |
| `smartctl: command not found` | smartmontools uninstalled — re-run `task deploy:host-hardening` |

## Mitigation

```bash
ssh ten 'sudo systemctl restart smartctl_exporter'
```

If unit is missing entirely, re-run the playbook:
```bash
task deploy:host-hardening
```
