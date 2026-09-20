# Runbooks

One markdown page per alert. Alert emails include a `runbook_url` link.

## Structure

Each page answers: **What fired?**, **How bad?**, **First steps**, **Root-cause investigation**, **Fix**, **Verification**.

## Completed

- [VaultSealed](VaultSealed.md)
- [ClusterSecretStoreNotReady](ClusterSecretStoreNotReady.md)
- [VeleroBSLUnavailable](VeleroBSLUnavailable.md)
- [PublicEndpointDown](PublicEndpointDown.md)
- [LanOnlyHostReachable](LanOnlyHostReachable.md)
- [PrometheusNotificationsFailing](PrometheusNotificationsFailing.md)
- [ArgoCDAppDegraded](ArgoCDAppDegraded.md)
- [KagentControllerDown](KagentControllerDown.md)
- [KagentControllerCrashLooping](KagentControllerCrashLooping.md)
- [KagentToolsCrashLooping](KagentToolsCrashLooping.md)
- [KagentOAuthProxyDown](KagentOAuthProxyDown.md)
- [KagentUIDown](KagentUIDown.md)

### masi (every alert of the group; CI: `.woodpecker/runbooks-exist.sh`)

- [MasiBudgetDay](MasiBudgetDay.md)
- [MasiBudgetMonth](MasiBudgetMonth.md)
- [MasiBudgetGaugeAbsent](MasiBudgetGaugeAbsent.md)
- [MasiCostRate](MasiCostRate.md)
- [MasiLedgerFailures](MasiLedgerFailures.md)
- [MasiModelMismatch](MasiModelMismatch.md)
- [MasiSourceDisabledAuto](MasiSourceDisabledAuto.md)
- [MasiSourceStale](MasiSourceStale.md)
- [MasiSourceHostNotAllowed](MasiSourceHostNotAllowed.md)
- [MasiReportsStale](MasiReportsStale.md)
- [MasiBrowserUnreachable](MasiBrowserUnreachable.md)
- [MasiBrowserSaturated](MasiBrowserSaturated.md)

## Stub (summary only)

All remaining alerts live in `prometheus-rules.yaml` and carry a
runbook_url link. Add a page when you hit an alert and want to capture
the diagnosis steps.
