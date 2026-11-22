# NodeAutoUpgradesFailing

**Severity:** warning · **For:** 10m

## What fired

ten's automatic Debian upgrades have had no successful package-list update, or no successful unattended-upgrades
run, for 26 h (before the first success, 26 h after they were set up) - or report nothing at all:

```
absent(max_over_time(apt_update_last_success_timestamp_seconds{job="node-exporter"}[26h]) > time() - 26 * 3600)
or absent(max_over_time(apt_unattended_upgrade_last_success_timestamp_seconds{job="node-exporter"}[26h]) > time() - 26 * 3600)
```

ops `setup-host-hardening.yml` (`tasks/auto-upgrades.yml`, `task deploy:host-hardening`) runs Debian's own
unattended-upgrades on its own timers, ten's local time: `apt-daily.timer` updates the package lists twice a day,
`apt-daily-upgrade.timer` installs Debian's updates between 06:00 and 07:00 (Debian's own origins - trixie and
trixie-security; nftables never; Docker's and Kubernetes' packages are held and move with the upgrade cycle). apt's
daily script touches `/var/lib/apt/periodic/update-stamp` and `upgrade-stamp` only on success - a lists update with
any failed download is a failure (`APT::Update::Error-Mode "any"`); `apt-upgrades-metrics.timer` reports their
times (before the first success, the set-up's) to node_exporter's textfile collector every 5 minutes
(`/var/lib/node_exporter/textfile/apt_upgrades.prom`).

## How bad

Security updates are not reaching ten. Nothing breaks at once; the gap grows every day it stays.

## First steps

```bash
ssh ten 'cat /var/lib/node_exporter/textfile/apt_upgrades.prom; ls -l --time-style=full-iso /var/lib/apt/periodic/'
ssh ten 'systemctl list-timers apt-daily.timer apt-daily-upgrade.timer apt-upgrades-metrics.timer --no-pager'
ssh ten 'sudo journalctl -u apt-daily.service -u apt-daily-upgrade.service --since "-2 days" --no-pager | tail -40'
ssh ten 'sudo tail -50 /var/log/unattended-upgrades/unattended-upgrades.log'
```

Once the cause is fixed, run the morning's units by hand - the lists, then the upgrade - and the alert clears at the
next metrics run:

```bash
ssh ten 'sudo systemctl start apt-daily.service apt-daily-upgrade.service && sudo systemctl start apt-upgrades-metrics.service'
```

## Root-cause investigation

| Symptom | Cause |
|---|---|
| `apt_update_*` old, `apt-daily.service` failed: `Temporary failure resolving`, `Could not connect` | deb.debian.org or security.debian.org unreachable from ten (DNS, the LAN, nftables) - `sudo apt-get update` shows which |
| `apt_unattended_upgrade_*` old, the log ends in `dpkg returned an error` | a package's maintainer script failed: `sudo dpkg --audit`, `sudo apt-get -f install`, then the run again |
| the log says `Lock could not be acquired` | someone's apt or dpkg was running at the upgrade's time (a manual `apt upgrade` left open?) - the next run takes it |
| timers `n/a` (not scheduled) or missing | the timers turned off by hand: `sudo systemctl enable --now apt-daily.timer apt-daily-upgrade.timer` |
| no `apt_*` lines at all, the file missing | `apt-upgrades-metrics.timer` not running, or never deployed: `task deploy:host-hardening` |
| the file current, the alert still firing | Prometheus does not scrape ten's node_exporter - `NodeExporterDown` fires too |
