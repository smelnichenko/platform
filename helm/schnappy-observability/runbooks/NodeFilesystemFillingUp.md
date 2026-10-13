# NodeFilesystemFillingUp

**Severity:** warning · **For:** 1h

## What fired

At the last 6 hours' rate a filesystem on ten (under 40 % free) runs out within 24 hours.

## Impact

None yet - this is the time to act, before NodeFilesystemCriticallyFull.

## First steps

What grows: compare `du` of the large directories an hour apart, or Grafana's
`node_filesystem_avail_bytes{mountpoint="/"}` against the volumes' own sizes.

```bash
ssh ten 'sudo du -sh /opt/local-path-provisioner/* /var/lib/containerd /var/log | sort -h | tail'
```

## Common causes

| Symptom | Cause |
|---|---|
| a jump during an upgrade | new images pulled - it levels off |
| a steady climb | a volume without retention (logs, metrics, a backup target) |
