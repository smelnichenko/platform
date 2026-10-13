# NodeFilesystemAlmostFull

**Severity:** warning · **For:** 15m

## What fired

A filesystem on ten (node_exporter, `job="node-exporter"`) has under 25 % free.

## Impact

None yet. At 15 % free the kubelet deletes unused images and then evicts pods (containerd's images share `/`
with everything else). NodeFilesystemCriticallyFull fires at 20 %.

## First steps

```bash
ssh ten 'df -h /; sudo du -xsh /var/lib/containerd /opt/local-path-provisioner /var/log /var/lib/kubelet 2>/dev/null'
ssh ten 'sudo du -sh /opt/local-path-provisioner/* | sort -h | tail'   # the biggest volumes
```

## Common causes

| Symptom | Cause |
|---|---|
| `/var/lib/containerd` large | images of past versions (upgrades) - the kubelet's GC removes unused ones at 85 % used |
| one volume grows | ClickHouse logs, s3gw, the CI cache - check that volume's retention |
| `/var/log` large | journald or a container's log rotation |

## Mitigation

Unused images: `ssh ten 'sudo crictl rmi --prune'` - never during an upgrade step (it removes images a step
pre-pulled). A volume's data is never deleted by hand without the owner's OK.
