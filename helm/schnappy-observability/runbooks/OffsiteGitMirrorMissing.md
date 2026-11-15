# OffsiteGitMirrorMissing

**Severity:** warning · **For:** 10m

## What fired

The offsite git mirror on ten has had no clean run for 26 h, or never recorded one
(`absent(max_over_time(offsite_git_mirror_last_success_timestamp_seconds{job="node-exporter"}[26h]) > time() - 26 * 3600)`).

The mirror (`offsite-backup.timer` / `offsite-backup.service` on ten, installed by ops `setup-velero.yml`, `task
deploy:velero`) pushes every repository of the Forgejo organisation to a repository of its own on the Pis'
`backup-git-mirror` Gluster volume (`/mnt/backups/git-mirror`, through the Pi holding the VIP) at 04:00 - every ref,
none deleted, every replaced commit kept in its reflog - then writes `last-success` there and its result to
`/var/lib/node_exporter/textfile/offsite_git_mirror.prom` on ten. On the Pis its key runs nothing but
`/usr/local/bin/git-mirror-gate`. A failed run is tried again by itself until one succeeds: 45 min later, then 1.5 h,
3 h, and every 6 h from then on. The unit has no start limit - a start is never refused.

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

The sync names each repository that failed and why (`FAILED: <repo>(<step>)`); the gate names the Pi and what it
refused (`git-mirror-gate on <pi>: ...`).

## Root-cause investigation

| Symptom | Cause |
|---|---|
| `FAILED: no token in /var/lib/git-mirror/token`, HTTP 401 | the mirror reader's token gone or revoked: `task deploy:velero` makes the reader anew and a new token (the `git-mirror` account, no admin) |
| `<repo>(its repository on the Pi)` with `Permission denied (publickey)` | the mirror's key (`/var/lib/git-mirror/id_ed25519` on ten) not authorized on the Pi holding the VIP: `task deploy:velero` authorizes it on both and proves each |
| `<repo>(its repository on the Pi)` with `git-mirror-gate on <pi>: /mnt/backups/git-mirror not mounted` | the `backup-git-mirror` volume not mounted on that Pi (`findmnt /mnt/backups/git-mirror`) - setup-gluster |
| `<repo>(its repository on the Pi)` with `was not made by this mirror` | a repository on the volume the mirror did not make: `task deploy:velero` keeps it aside (`<name>.pre-mirror-<time>.git`) |
| `<repo>(emptied in Forgejo - its backup of N refs kept)` | Forgejo serves the repository empty while its backup holds history: deleted and made again, or a restore gone wrong. The backup is the copy to restore from (`git clone /mnt/backups/git-mirror/<repo>.git` on a Pi, then push it to Forgejo) |
| `<repo>(fetch)`, `<repo>(clone)` | Forgejo unreachable from ten, or the repository gone mid-run: the next try |
| `<repo>(push timed out)`, the ones after it `(not tried - <repo>'s push timed out)` | a push passed its 10 min: the Pi's volume hung, most likely - the run stops pushing (each after it would hang, its git-receive-pack stuck on the Pi). `findmnt /mnt/backups/git-mirror`, `gluster volume heal backup-git-mirror info` on a Pi |
| `<repo>(push)` with `index.lock` or `*.lock` | a lock left by a killed push in that backup: remove the stale lock under `/mnt/backups/git-mirror/<repo>.git` on a Pi |
| the unit `activating (auto-restart)` | a run failed and the next try is scheduled (`systemctl status` names when): the cause is in the journal before it; it keeps trying, 6 h apart at most, until a run succeeds |
| `Failed with result 'timeout'`, no `FAILED:` line | the run passed its 2 h bound (fetches stalling one after another - Forgejo hung): systemd ended it; the next try as above |
| no series at all, the unit never ran | the timer missing or disabled on ten: `task deploy:velero` |
| `node-exporter` target down | node_exporter on ten: `task deploy:host-hardening` (its textfile collector) |

After a fix: `ssh ten sudo systemctl start offsite-backup.service` runs it now (a retry pending runs at once; it waits
for the run's end and fails with it) - or the next retry picks it up; the alert clears within a scrape.
