# OffsiteGitMirrorMissing

**Severity:** warning · **For:** 10m

## What fired

The offsite git mirror on ten has had no clean run for 26 h, or never recorded one
(`absent(max_over_time(offsite_git_mirror_last_success_timestamp_seconds{job="node-exporter"}[26h]) > time() - 26 * 3600)`).

The mirror (`offsite-backup.timer` / `offsite-backup.service` on ten, installed by ops `setup-velero.yml`, `task
deploy:velero`) pushes every repository of the Forgejo organisation to a bare repository of its own on the Pis'
`backup-git-mirror` Gluster volume (`/mnt/backups/git-mirror`, through the Pi holding the VIP) at 04:00, then writes
`last-success` there and its result to `/var/lib/node_exporter/textfile/offsite_git_mirror.prom` on ten.

## How bad

The Pis' copy of the code is older than a day. Forgejo itself still serves its own repositories (its Gluster volume,
Patroni); this is the copy kept apart from them.

## First steps

```bash
ssh ten 'systemctl status offsite-backup.service --no-pager; systemctl list-timers offsite-backup.timer --no-pager'
ssh ten 'sudo journalctl -u offsite-backup.service --since "-2 days" --no-pager | tail -30'
ssh ten 'cat /var/lib/node_exporter/textfile/offsite_git_mirror.prom'
ssh pi1 'cat /mnt/backups/git-mirror/last-success; ls /mnt/backups/git-mirror'
```

The sync names each repository that failed and why (`FAILED: <repo>(<step>)`).

## Root-cause investigation

| Symptom | Cause |
|---|---|
| `FAILED: no token in /var/lib/git-mirror/token`, HTTP 401 | the mirror reader's token gone or revoked: `task deploy:velero` makes a new one (the `git-mirror` account, no admin) |
| `<repo>(its repository on the Pi)`, `Permission denied (publickey)` | the mirror's key (`/home/sm/.ssh/id_ed25519` on ten) not authorized for `sm` on the Pi holding the VIP: `task deploy:velero` authorizes it on both |
| `<repo>(push)` with `mountpoint` in the log | the `backup-git-mirror` volume not mounted on that Pi (`findmnt /mnt/backups/git-mirror`) - setup-gluster |
| the file has an old time, the unit `success` | the textfile not written: its owner or `/var/lib/node_exporter/textfile` (setup-host-hardening) |
| no series at all, the unit never ran | the timer missing or disabled on ten: `task deploy:velero` |
| `node-exporter` target down | node_exporter on ten: `task deploy:host-hardening` (its textfile collector flag) |

After a fix: `ssh ten sudo systemctl start offsite-backup.service` runs it now; the alert clears within a scrape.
