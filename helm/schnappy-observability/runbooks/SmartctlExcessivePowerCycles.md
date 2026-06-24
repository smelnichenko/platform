# SmartctlExcessivePowerCycles

**Severity:** warning · **For:** 10m

## What fired

`increase(smartctl_device_power_cycle_count{device="$labels.device"}[24h]) > 5` — the drive has been power-cycled more than 5 times in 24 h.

This is a **proxy for unsafe shutdowns**: smartctl_exporter v0.14 doesn't surface NVMe `unsafe_shutdowns` directly, so we use total power cycles. Normal operation on ten is a planned reboot every few days; >5 cycles in a day means the host is unstable (kernel hangs, hard resets).

## Impact

Host is rebooting itself, likely from a recurring kernel hang. Each unsafe shutdown risks data loss for in-flight writes (PostgreSQL/Scylla recover via WAL/commitlog, but app-level half-writes can persist).

## First steps

```bash
ssh ten 'last -x reboot shutdown | head -10'
ssh ten 'sudo ls -la /var/lib/systemd/pstore/'
ssh ten 'sudo journalctl -k -b -1 --no-pager | grep -E "BUG:|WARNING:|Call Trace|RIP:" | head -30'
ssh ten 'cat /proc/cmdline | tr " " "\n" | grep -E "nvme|panic|softlockup"'
ssh ten 'sudo nvme smart-log /dev/disk/by-id/<paste $labels.device>' | grep -i "unsafe shutdowns\|power cycles"
```

(The `device` label is the stable by-id basename; address the drive via `/dev/disk/by-id/<device>` — kernel `/dev/nvmeN` names aren't in the label.)

## Common causes (this cluster)

| Symptom | Cause | Memory |
|---|---|---|
| Pstore captures `Call Trace` | Real kernel oops, look at trace site |  |
| Pstore empty + `last -x` shows `crash` | Soft hang (PID 1 alive, kernel frozen). Check `softlockup_panic` + `hung_task_panic` are still 1. |  |

The historical cause on this host — the Samsung 980 PRO 1B2QGXA7 APST firmware bug — is RESOLVED: both drives were flashed to 5B2QGXA7 on 2026-05-08 and the `nvme_core.default_ps_max_latency_us=0` cmdline workaround was deliberately removed (so do **not** re-add it). If hangs recur, the signature now points at something OTHER than 980 PRO firmware — see `project_ten_host_wedge`. First confirm firmware is still 5B2QGXA7: `ssh ten 'sudo smartctl -i /dev/disk/by-id/<device> | grep -i firmware'`.

## Mitigation

Pstore captures the trace site for a real oops — file it and investigate. If firmware has somehow reverted below 5B2QGXA7, re-flash via fumagician (see `project_ten_host_wedge`); the kernel-cmdline APST workaround is no longer the remediation.
