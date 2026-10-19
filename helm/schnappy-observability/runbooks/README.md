# Runbooks

One markdown page per alert. Alert emails include a `runbook_url` link.

## Structure

Each page answers: **What fired?**, **How bad?**, **First steps**, **Root-cause investigation**, **Fix**, **Verification**.

## Completed

- [VaultSealed](VaultSealed.md)
- [ClusterSecretStoreNotReady](ClusterSecretStoreNotReady.md)
- [VeleroScheduledBackupFailed](VeleroScheduledBackupFailed.md)
- [VeleroDailyBackupMissing](VeleroDailyBackupMissing.md)
- [VeleroWeeklyBackupMissing](VeleroWeeklyBackupMissing.md)
- [VeleroBackupFailing](VeleroBackupFailing.md)
- [VeleroBackupPartiallyFailed](VeleroBackupPartiallyFailed.md)
- [VeleroDown](VeleroDown.md)
- [PublicEndpointDown](PublicEndpointDown.md)
- [LanOnlyHostReachable](LanOnlyHostReachable.md)
- [PrometheusNotificationsFailing](PrometheusNotificationsFailing.md)
- [ArgoCDAppDegraded](ArgoCDAppDegraded.md)
- [KagentControllerDown](KagentControllerDown.md)
- [KagentControllerCrashLooping](KagentControllerCrashLooping.md)
- [KagentToolsCrashLooping](KagentToolsCrashLooping.md)
- [KagentOAuthProxyDown](KagentOAuthProxyDown.md)
- [KagentUIDown](KagentUIDown.md)
- [PostgresArchivingFailed](PostgresArchivingFailed.md)
- [PostgresBackupFailed](PostgresBackupFailed.md)
- [PostgresBackupMissed](PostgresBackupMissed.md)
- [PostgresBackupNeverSucceeded](PostgresBackupNeverSucceeded.md)
- [PostgresBackupStuck](PostgresBackupStuck.md)
- [PostgresBackupsUnwatched](PostgresBackupsUnwatched.md)
- [ScyllaBackupMissed](ScyllaBackupMissed.md)
- [ScyllaBackupNeverSucceeded](ScyllaBackupNeverSucceeded.md)
- [ScyllaManagerTaskFailed](ScyllaManagerTaskFailed.md)
- [ScyllaManagerDown](ScyllaManagerDown.md)
- [ScyllaBackupsUnwatched](ScyllaBackupsUnwatched.md)

### masi (every alert of the group; CI: `.woodpecker/runbooks-exist.sh`)

- [MasiBudgetDay](MasiBudgetDay.md)
- [MasiBudgetMonth](MasiBudgetMonth.md)
- [MasiBudgetGaugeAbsent](MasiBudgetGaugeAbsent.md)
- [MasiCostRate](MasiCostRate.md)
- [MasiLedgerFailures](MasiLedgerFailures.md)
- [MasiDigestGivenUp](MasiDigestGivenUp.md)
- [MasiLlmAccountRefused](MasiLlmAccountRefused.md)
- [MasiModelMismatch](MasiModelMismatch.md)
- [MasiSourceDisabledAuto](MasiSourceDisabledAuto.md)
- [MasiSourceStale](MasiSourceStale.md)
- [MasiSourceHostNotAllowed](MasiSourceHostNotAllowed.md)
- [MasiJobClosedWithOpenListing](MasiJobClosedWithOpenListing.md)
- [MasiSourceNotClosing](MasiSourceNotClosing.md)
- [MasiSweepStarved](MasiSweepStarved.md)
- [MasiReportsStale](MasiReportsStale.md)
- [MasiBrowserUnreachable](MasiBrowserUnreachable.md)
- [MasiBrowserSaturated](MasiBrowserSaturated.md)

## Stub (summary only)

All remaining alerts live in `prometheus-rules.yaml` and carry a
runbook_url link. Add a page when you hit an alert and want to capture
the diagnosis steps.
