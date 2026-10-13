# NodeFilesystemCriticallyFull

**Severity:** critical · **For:** 5m

## What fired

A filesystem on ten has under 20 % free.

## Impact

At 15 % free the kubelet evicts pods (the DiskPressure taint stops new ones from starting). Databases and
brokers on local-path volumes go down with their pods.

## First steps

The same as [NodeFilesystemAlmostFull](NodeFilesystemAlmostFull.md): find what is large and what grows.

## Mitigation

1. Unused images: `ssh ten 'sudo crictl rmi --prune'` (not during an upgrade step).
2. Old journal: `ssh ten 'sudo journalctl --vacuum-size=1G'`.
3. A growing volume: shorten its retention through its chart; deleting a volume's data needs the owner's OK.
