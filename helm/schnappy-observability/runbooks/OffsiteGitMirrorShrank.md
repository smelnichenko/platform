# OffsiteGitMirrorShrank

**Severity:** warning · **For:** 1h

## What fired

The offsite git mirror's last good run mirrored fewer repositories than it did at some point in the past week
(`offsite_git_mirror_repositories{job="node-exporter"} < max_over_time(...[7d])`).

The mirror (ops `setup-velero.yml`, `offsite-backup.service` on ten) mirrors every repository its reader (`git-mirror`,
team `git-mirror-read`: code read on every repository of the organisation) can list. The run still succeeds on what it
lists - this alert is what says it listed less.

## How bad

Either a repository was deleted in Forgejo on purpose (its backup on the Pis is kept: nothing to do), or the reader
lost sight of some: their newest code is no longer being backed up.

## First steps

```bash
ssh ten 'cat /var/lib/node_exporter/textfile/offsite_git_mirror.prom'
ssh ten 'sudo journalctl -u offsite-backup.service --since "-2 days" --no-pager | grep mirrored:'
ssh pi1 'ls /mnt/backups/git-mirror'      # the backups, deleted repositories' included
```

Compare the last two `mirrored:` lines: the repository that dropped out is the one missing from the newer.

## Root-cause investigation

| Symptom | Cause |
|---|---|
| the repository is gone from Forgejo (deleted, or moved to another organisation) | on purpose: its backup is kept; the alert clears a week later |
| the repository is still in Forgejo | the reader's team grant: `git-mirror-read` must have code read on every repository (includes_all_repositories) and hold `git-mirror` - `task deploy:velero` sets it again and refuses while the reader reads fewer than the admin lists |
| several dropped at once | the team deleted or the reader removed from it: `task deploy:velero` |
