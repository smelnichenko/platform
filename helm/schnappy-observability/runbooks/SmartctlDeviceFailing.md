# SmartctlDeviceFailing

**Severity:** critical · **For:** 5m

## What fired

`smartctl_device_smart_status{device="$labels.device"} == 0` — the drive's own SMART self-test reports a pass/fail = fail. This is the firmware itself flagging an impending failure, not a derived heuristic.

## Impact

The drive is failing or about to fail. Continued use risks data loss. If it's the boot drive (`nvme1n1` on ten holds `/boot/efi` + `/`), a failure means the host won't boot.

## First steps

The `device` label is the stable by-id basename (e.g. `nvme-Samsung_SSD_980_PRO_1TB_S5GXNG0NA10983L`), so address the drive via `/dev/disk/by-id/<device>` — the kernel `/dev/nvmeN` names are not in the label and swap across reboots:

```bash
DEV=/dev/disk/by-id/<paste $labels.device>
ssh ten "sudo smartctl -a $DEV" | head -40
ssh ten "sudo nvme smart-log $DEV"
```

Look for:
- **Critical Warning** ≠ 0
- **Available Spare** below threshold (<10%)
- **Media and Data Integrity Errors** > 0
- **Error Information Log Entries** > 0

## Mitigation

1. Check Velero backup is current (`kubectl -n velero get schedule velero-schnappy-daily`).
2. If single drive failure: order replacement, plan migration window. Two-NVMe layout (`nvme0n1` = data `/mnt/storage`, `nvme1n1` = boot+root) means the data drive can be replaced without reinstalling.
3. If both fail simultaneously: see `project_ten_host_wedge` memory — both drives are Samsung 980 PRO, now on firmware 5B2QGXA7 (the buggy 1B2QGXA7 was flashed out 2026-05-08). Same model + same firmware + same age = correlated failure mode is still plausible.

## Related

- `SmartctlNvmeCriticalWarning` — softer warning bitfield
- `SmartctlMediaErrors` — data integrity counter
