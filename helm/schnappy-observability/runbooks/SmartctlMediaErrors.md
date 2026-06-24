# SmartctlMediaErrors

**Severity:** critical · **For:** 5m

## What fired

`smartctl_device_media_errors{device="$labels.device"} > 0` — the drive's NVMe controller has counted unrecoverable read or write errors. This is data the drive could not deliver or could not commit.

## Impact

Filesystem may have silent corruption. Anything stored on the affected device is suspect.

## First steps

The `device` label is the stable by-id basename; address the drive via `/dev/disk/by-id/<device>` (kernel `/dev/nvmeN` names aren't in the label):

```bash
DEV=/dev/disk/by-id/<paste $labels.device>
ssh ten "sudo nvme smart-log $DEV" | head -30
ssh ten "sudo nvme error-log $DEV | head -50"
ssh ten 'sudo dmesg --ctime | grep -iE "nvme|i/o error|ext4-fs error" | tail -30'
ssh ten 'sudo journalctl -k --since "1 day ago" | grep -iE "i/o error|ext4-fs error|btrfs.*error"'
```

## Mitigation

1. Confirm Velero backup is recent.
2. If filesystem is repairable (ext4 fsck on next reboot), schedule maintenance.
3. If errors keep climbing, drive is failing. Replace.
4. For ten specifically: data drive is `nvme0n1` (`/mnt/storage`), boot+root drive is `nvme1n1` (`/boot/efi` + `/`). Map the by-id `device` label to a kernel name with `ls -l /dev/disk/by-id/<device>`. Replacement strategy differs.
