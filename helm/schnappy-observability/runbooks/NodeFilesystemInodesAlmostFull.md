# NodeFilesystemInodesAlmostFull

**Severity:** warning · **For:** 15m

## What fired

A filesystem on ten has under 10 % of its inodes free.

## Impact

With no inode left no file can be created, whatever the free space: pods fail to start, databases fail to write.

## First steps

```bash
ssh ten 'df -i; sudo find / -xdev -type d -size +1M 2>/dev/null | head'   # directories with very many entries
```

## Common causes

Many small files: container image layers, a cache, a log directory without rotation.
