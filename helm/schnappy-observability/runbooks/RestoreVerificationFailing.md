# RestoreVerificationFailing

**Severity:** warning · **For:** 1h

## What fired

No successful disaster-recovery drill has recorded `restore_verify_success` for over 35 days. The drill (`task dr:drill`) stands up an ephemeral Vagrant cluster, restores the latest Velero + CNPG backups into it, and runs k6 against the booted app. A stale metric means the backup/restore path is **unverified**, not necessarily broken.

## Impact

We don't currently know whether the production backups can actually be restored. Backups *completing* (`velero backup`, CNPG barman) is necessary but not sufficient — only a restore proves recoverability.

## First steps

Run the drill from your workstation (it needs Vagrant/libvirt, so it cannot run in CI):

```bash
cd ~/src/ops
task dr:drill          # vagrant destroy→up→restore→verify (~30 min), then records the metric
```

A passing run pushes `restore_verify_success` to the prod pushgateway (`schnappy-pushgateway.schnappy-infra:9091`, job `dr-drill`), which resets this alert.

## If the drill itself fails

The drill failing is the real signal. Inspect the run log:

```bash
grep -nE 'FAILED!|fatal:|Data lost|failed=[1-9]' /tmp/dr-drill.log
```

Common causes:

| Symptom | Likely cause |
|---|---|
| Helm repo / chart pull 404 | Upstream moved (the harness rots over time) — fix the ref in `tests/ansible/test-dr.yml` / `deploy/ansible/playbooks/setup-kubeadm.yml` |
| Velero BSL never `Available` / backup stuck | Plugin/server version mismatch — align `velero-plugin-for-aws` to the Velero appVersion |
| `Data lost` / config-not-found assertion | A real restore or data-integrity regression — investigate the backup config |

Fix the harness or the backup config, then re-run `task dr:drill`.

## Notes

- The metric is **manually triggered** by design — there's no scheduler; this alert is the reminder.
- The pushgateway persists `push_time_seconds` to a PVC, so a pushgateway restart does not drop the last-success timestamp.
- The alert is silent before the first-ever drill (the metric is absent until then).
