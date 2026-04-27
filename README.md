# Platform (Helm Charts)

Helm charts for deploying pmon.dev to Kubernetes.

## Architecture

This repo holds a family of Helm charts. Each chart is consumed by an Argo CD Application; image tags and per-environment values live in the `schnappy/infra` repo. Production splits into multiple namespaces (`schnappy-production-apps`, `schnappy-production-data`, `schnappy-production-mesh`) and a parallel `schnappy-test-*` set for Vagrant E2E.

## Charts

| Chart | Purpose |
|-------|---------|
| `schnappy` | Core application services (admin, monitor, chat, chess, site, game) |
| `schnappy-data` | Stateful stores: PostgreSQL (CNPG), Valkey, Kafka (Strimzi), ScyllaDB, MinIO, apt-cache |
| `schnappy-mesh` | Istio ingress gateway, `HTTPRoute`s, `RequestAuthentication`, `AuthorizationPolicy`, rate limits |
| `schnappy-realtime` | Centrifugo realtime fan-out — Kafka envelopes → Centrifugo → WebSocket clients |
| `schnappy-observability` | ELK, Mimir, Grafana, Alertmanager, blackbox/PodMonitors, runbooks |
| `schnappy-sonarqube` | SonarQube + dedicated PostgreSQL |
| `schnappy-auth` | **Test-only** in-cluster Keycloak for Vagrant E2E (production Keycloak is bare-metal on the Pis) |
| `schnappy-test` | k6 smoke tests |

## Repo Structure

```
platform/
  helm/
    schnappy/                # core app chart
    schnappy-data/
    schnappy-mesh/
    schnappy-realtime/
    schnappy-observability/
    schnappy-sonarqube/
    schnappy-auth/
    schnappy-test/
  grafana/                   # dashboard JSON + dev config
  kafka/                     # Kafka topic init
  scylla/                    # ScyllaDB schema init
  apt-cache/                 # apt-cacher-ng image
  keycloak-theme/            # Keycloak login/account theme assets
```

## Development

```bash
# Lint a chart
helm lint helm/schnappy/

# Render templates locally with the chart's defaults
helm template schnappy helm/schnappy/ -f helm/schnappy/values.yaml

# Render with production values (pulled from the infra repo)
helm template schnappy helm/schnappy/ \
  -f /home/sm/src/infra/clusters/production/schnappy-production-apps/values.yaml
```

## Deployment

Charts are not installed directly. Argo CD reconciles them:

1. An Argo CD Application points at a chart in this repo + a values file in `schnappy/infra`
2. Woodpecker CD commits updated image tags to `schnappy/infra`
3. Argo CD detects the change (poll/webhook) and syncs the Application
4. Helm renders, Kubernetes performs a rolling update

For local development, use `docker-compose.yml` in the ops repo instead.
