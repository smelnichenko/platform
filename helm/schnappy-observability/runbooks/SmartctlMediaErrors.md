# SmartctlMediaErrors

**Severity:** critical · **For:** 5m

## What fired

`smartctl_device_media_errors{device="$labels.device"} > 0` — the drive's NVMe controller has counted unrecoverable read or write errors. This is data the drive could not deliver or could not commit.

## Impact

Filesystem may have silent corruption. Anything stored on the affected device is suspect.

## First steps

```bash
ssh ten 'sudo nvme smart-log /dev/${labels_device}' | head -30
ssh ten 'sudo nvme error-log /dev/${labels_device} | head -50'
ssh ten 'sudo dmesg --ctime | grep -iE "nvme|i/o error|ext4-fs error" | tail -30'
ssh ten 'sudo journalctl -k --since "1 day ago" | grep -iE "i/o error|ext4-fs error|btrfs.*error"'
```

## Mitigation

1. Confirm Velero backup is recent.
2. If filesystem is repairable (ext4 fsck on next reboot), schedule maintenance.
3. If errors keep climbing, drive is failing. Replace.
4. For ten specifically: data drive is `/dev/nvme0`, boot drive is `/dev/nvme1`. Replacement strategy differs.
