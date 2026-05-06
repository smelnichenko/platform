# SmartctlNvmeCriticalWarning

**Severity:** critical · **For:** 5m

## What fired

`smartctl_device_critical_warning{device="$labels.device"} > 0` — the NVMe controller's composite warning bitfield is non-zero. Bit meanings (per NVMe spec):

| Bit | Meaning |
|---|---|
| 0 | Available spare below threshold |
| 1 | Temperature exceeds critical threshold |
| 2 | Reliability degraded |
| 3 | Read-only mode |
| 4 | Volatile memory backup device failed |
| 5 | Persistent memory region read-only / unreliable |

## First steps

```bash
ssh ten 'sudo nvme smart-log /dev/${labels_device}' | head -25
```

Decode the `Critical Warning:` value. Then:
- bit 0 (spare low): drive is wearing out, plan replacement
- bit 1 (temperature): check chassis airflow, dust filter
- bit 2 (reliability): drive is degrading; replace
- bit 3 (read-only): drive has flipped to RO; plan migration urgently

## Mitigation

For wear/temperature/reliability — order replacement, schedule maintenance window, migrate.
For temperature only — clean chassis fans, check ambient.
