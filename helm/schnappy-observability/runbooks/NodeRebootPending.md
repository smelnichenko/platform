# NodeRebootPending

**Severity:** warning · **For:** 26h

## What fired

ten has owed a reboot for 26 h: `/run/reboot-required` has stood since the morning before
(`max_over_time(node_reboot_required{job="node-exporter"}[10m]) == 1` for 26 h).

An update writes that file when it is not live until a reboot - every kernel (unattended-upgrades' kernel hook), a
manual `apt upgrade`'s too; `/run/reboot-required.pkgs` names what asked. unattended-upgrades (ops
`setup-host-hardening.yml`, `tasks/auto-upgrades.yml`) checks for it after every morning run (between 06:00 and 07:00,
ten's local time) and schedules `shutdown -r 07:30` - no check of the cluster or the Pis first. So a reboot owed for
26 h is one that did not happen: cancelled (`shutdown -c`), never scheduled (that morning's upgrade failed before its
check - `NodeAutoUpgradesFailing` then too), the upgrade timer off, or the reboot turned off.

## How bad

ten runs its old kernel (or a library's old code in a running service): the update installed is not live, its fixes
not applied. Nothing breaks.

## First steps

```bash
ssh ten 'cat /run/reboot-required.pkgs; uname -r; ls /boot/vmlinuz-*'
ssh ten 'busctl get-property org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager ScheduledShutdown'
ssh ten 'sudo grep -E "reboot|shutdown" /var/log/unattended-upgrades/unattended-upgrades.log | tail -10'
ssh ten 'systemctl list-timers apt-daily-upgrade.timer --no-pager'
```

To reboot now instead of waiting for the next 07:30, follow ops `docs/NodeReboot.md` (a plain `sudo systemctl reboot`;
about 8 minutes until Kafka serves again).

## Root-cause investigation

| Symptom | Cause |
|---|---|
| the log says `Found /var/run/reboot-required, rebooting` and `ScheduledShutdown` is `(st) "" 0` | the scheduled reboot was cancelled (`shutdown -c`) - the next morning's run schedules it again |
| no `rebooting` line since the file appeared | that morning's run failed before its check (see `NodeAutoUpgradesFailing`), or did not run: the timers |
| the log says `Failed to issue shutdown` | `/sbin/shutdown` refused - logind's state: `journalctl -u systemd-logind --since "-1 day"` |
| `apt-daily-upgrade.timer` inactive | turned off by hand: `sudo systemctl enable --now apt-daily-upgrade.timer` |
| `apt-config dump Unattended-Upgrade::Automatic-Reboot` says `false` | `auto_upgrades_reboot` false (only the Vagrant copy's inventory sets it) - re-run `task deploy:host-hardening` |
