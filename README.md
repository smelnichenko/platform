# Platform (Helm Chart)

Helm chart for deploying the full pmon.dev application stack to Kubernetes.

## Architecture

Single Helm chart that templates all application services and infrastructure components into the `monitor` namespace. Managed by Flux CD HelmRelease -- image tags and configuration values live in the `schnappy/infra` repo.

## Components

**Application services:** API gateway, admin, monitor (core), chat, chess, site (frontend)

**Databases:** PostgreSQL 17 (shared instance, per-service databases), Redis 7, Kafka 4.2 (KRaft), ScyllaDB 6.2

**Observability:** Prometheus, Grafana, Alertmanager, kube-state-metrics, Elasticsearch 8, Fluent-bit, Kibana, SonarQube

**Infrastructure:** Network policies (default-deny), ExternalSecrets (Vault integration), apt-cacher-ng, PostgreSQL backup CronJob

## Chart Structure

```
platform/
  helm/
    Chart.yaml
    values.yaml
    templates/           # All k8s resource templates
  grafana/               # Grafana dashboard JSON and dev config
  kafka/                 # Kafka topic initialization
  scylla/                # ScyllaDB schema initialization
  apt-cache/             # apt-cacher-ng Dockerfile
```

## Development

```bash
# Lint the chart
helm lint helm/

# Render templates locally
helm template monitor helm/ -f helm/values.yaml

# Render with production values (from infra repo)
helm template monitor helm/ -f /path/to/infra/clusters/production/monitor/values.yaml
```

## Deployment

This chart is not installed directly. Flux CD manages it:

1. Flux HelmRelease references this chart via GitRepository source
2. Woodpecker CD commits updated image tags to the `schnappy/infra` repo
3. Flux source-controller polls the infra repo (1-minute interval)
4. Flux helm-controller reconciles the HelmRelease with new values
5. Kubernetes performs a rolling update

For local development, use `docker-compose.yml` in the ops repo instead.
