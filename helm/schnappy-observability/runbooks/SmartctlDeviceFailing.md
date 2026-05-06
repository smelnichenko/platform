# SmartctlDeviceFailing

**Severity:** critical · **For:** 5m

## What fired

`smartctl_device_smart_status{device="$labels.device"} == 0` — the drive's own SMART self-test reports a pass/fail = fail. This is the firmware itself flagging an impending failure, not a derived heuristic.

## Impact

The drive is failing or about to fail. Continued use risks data loss. If it's the boot drive (`/dev/nvme1` on ten holds `/`), a failure means the host won't boot.

## First steps

```bash
ssh ten 'sudo smartctl -a /dev/${labels_device}' | head -40
ssh ten 'sudo nvme smart-log /dev/${labels_device}'
```

Look for:
- **Critical Warning** ≠ 0
- **Available Spare** below threshold (<10%)
- **Media and Data Integrity Errors** > 0
- **Error Information Log Entries** > 0

## Mitigation

1. Check Velero backup is current (`kubectl -n schnappy-infra get schedule -A`).
2. If single drive failure: order replacement, plan migration window. Two-NVMe layout (nvme0=data, nvme1=root) means data drive can be replaced without reinstalling.
3. If both fail simultaneously: see `project_ten_host_wedge` memory — both drives are Samsung 980 PRO firmware 1B2QGXA7. Same model + same firmware + same age = correlated failure mode is plausible.

## Related

- `SmartctlNvmeCriticalWarning` — softer warning bitfield
- `SmartctlMediaErrors` — data integrity counter
