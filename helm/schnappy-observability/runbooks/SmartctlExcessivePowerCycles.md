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
ssh ten 'sudo nvme smart-log /dev/${labels_device}' | grep -i "unsafe shutdowns\|power cycles"
```

## Common causes (this cluster)

| Symptom | Cause | Memory |
|---|---|---|
| All 980 PRO drives | Samsung firmware 1B2QGXA7 APST bug | `project_ten_host_wedge` |
| Pstore captures `Call Trace` | Real kernel oops, look at trace site |  |
| Pstore empty + `last -x` shows `crash` | Soft hang (PID 1 alive, kernel frozen). Check `softlockup_panic` + `hung_task_panic` are still 1. |  |
| /proc/cmdline missing `nvme_core.default_ps_max_latency_us=0` | APST mitigation lapsed (kernel/grub upgrade?) — re-run `task deploy:host-hardening` |  |

## Mitigation

If APST mitigation is intact and pstore captures a non-NVMe trace, this is a different bug — file the trace and investigate.
