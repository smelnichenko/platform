# Platform (Helm Charts)

Helm charts for all schnappy components. Deployed via Argo CD GitOps from the `schnappy/infra` repo.

## Charts

| Chart | Path | Argo CD App | Changes when |
|---|---|---|---|
| `schnappy` | `helm/schnappy` | `schnappy` | Code pushes (daily) — app, admin, chat, chess, site, game |
| `schnappy-data` | `helm/schnappy-data` | `schnappy-data` | Version bumps (monthly) — postgres, redis, kafka, scylla, minio, apt-cache |
| `schnappy-auth` | `helm/schnappy-auth` | — | **TEST-ONLY** (Vagrant E2E in-cluster Keycloak). Production Keycloak is bare-metal on Pis. |
| `schnappy-observability` | `helm/schnappy-observability` | `schnappy-observability` | Dashboard/config (weekly) — ELK, prometheus, grafana, alertmanager |
| `schnappy-sonarqube` | `helm/schnappy-sonarqube` | `schnappy-sonarqube` | QG/rule changes (rare) — sonarqube |
| `schnappy-mesh` | `helm/schnappy-mesh` | `schnappy-mesh` | Mesh config (rare) — Istio gateway, HTTPRoutes, ServiceAccounts, AuthorizationPolicies |

All charts deploy to namespace `schnappy` with `nameOverride: schnappy`.

## Other Directories

```
apt-cache/          # Dockerfile for apt-cacher-ng
grafana/            # Grafana dashboard JSON provisioning
kafka/              # Kafka topic init scripts
keycloak-theme/     # Realm JSON templates
scylla/             # ScyllaDB schema CQL
```

## Cross-Chart Design

All pods have `app.kubernetes.io/part-of: schnappy` label. Network policies use `nameOverride`-derived selector labels for cross-chart pod references. Default-deny NP is in `infra` repo `cluster-config/`.

## Full Infrastructure Docs

See `schnappy/ops` repo `CLAUDE.md` for complete infrastructure documentation.
