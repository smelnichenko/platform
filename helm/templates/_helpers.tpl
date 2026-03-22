{{/*
Expand the name of the chart.
*/}}
{{- define "schnappy.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "schnappy.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "schnappy.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "schnappy.labels" -}}
helm.sh/chart: {{ include "schnappy.chart" . }}
{{ include "schnappy.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "schnappy.selectorLabels" -}}
app.kubernetes.io/name: {{ include "schnappy.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
App labels
*/}}
{{- define "schnappy.monitor.labels" -}}
{{ include "schnappy.labels" . }}
app.kubernetes.io/component: app
{{- end }}

{{/*
App selector labels
*/}}
{{- define "schnappy.monitor.selectorLabels" -}}
{{ include "schnappy.selectorLabels" . }}
app.kubernetes.io/component: app
{{- end }}

{{/*
PostgreSQL labels
*/}}
{{- define "schnappy.postgres.labels" -}}
{{ include "schnappy.labels" . }}
app.kubernetes.io/component: postgres
{{- end }}

{{/*
PostgreSQL selector labels
*/}}
{{- define "schnappy.postgres.selectorLabels" -}}
{{ include "schnappy.selectorLabels" . }}
app.kubernetes.io/component: postgres
{{- end }}

{{/*
Prometheus labels
*/}}
{{- define "schnappy.prometheus.labels" -}}
{{ include "schnappy.labels" . }}
app.kubernetes.io/component: prometheus
{{- end }}

{{/*
Prometheus selector labels
*/}}
{{- define "schnappy.prometheus.selectorLabels" -}}
{{ include "schnappy.selectorLabels" . }}
app.kubernetes.io/component: prometheus
{{- end }}

{{/*
Grafana labels
*/}}
{{- define "schnappy.grafana.labels" -}}
{{ include "schnappy.labels" . }}
app.kubernetes.io/component: grafana
{{- end }}

{{/*
Grafana selector labels
*/}}
{{- define "schnappy.grafana.selectorLabels" -}}
{{ include "schnappy.selectorLabels" . }}
app.kubernetes.io/component: grafana
{{- end }}

{{/*
PostgreSQL service name
*/}}
{{- define "schnappy.postgres.serviceName" -}}
{{- printf "%s-postgres" (include "schnappy.fullname" .) }}
{{- end }}

{{/*
Prometheus service name
*/}}
{{- define "schnappy.prometheus.serviceName" -}}
{{- printf "%s-prometheus" (include "schnappy.fullname" .) }}
{{- end }}

{{/*
App service name
*/}}
{{- define "schnappy.monitor.serviceName" -}}
{{- printf "%s-monitor" (include "schnappy.fullname" .) }}
{{- end }}

{{/*
PostgreSQL secret name
*/}}
{{- define "schnappy.postgres.secretName" -}}
{{- if .Values.postgres.existingSecret }}
{{- .Values.postgres.existingSecret }}
{{- else }}
{{- printf "%s-postgres" (include "schnappy.fullname" .) }}
{{- end }}
{{- end }}

{{/*
Grafana secret name
*/}}
{{- define "schnappy.grafana.secretName" -}}
{{- if .Values.grafana.existingSecret }}
{{- .Values.grafana.existingSecret }}
{{- else }}
{{- printf "%s-grafana" (include "schnappy.fullname" .) }}
{{- end }}
{{- end }}

{{/*
Auth secret name
*/}}
{{- define "schnappy.auth.secretName" -}}
{{- if .Values.auth.existingSecret }}
{{- .Values.auth.existingSecret }}
{{- else }}
{{- printf "%s-auth" (include "schnappy.fullname" .) }}
{{- end }}
{{- end }}

{{/*
Mail secret name
*/}}
{{- define "schnappy.mail.secretName" -}}
{{- if .Values.mail.existingSecret }}
{{- .Values.mail.existingSecret }}
{{- else }}
{{- printf "%s-mail" (include "schnappy.fullname" .) }}
{{- end }}
{{- end }}

{{/*
AI secret name
*/}}
{{- define "schnappy.ai.secretName" -}}
{{- if .Values.ai.existingSecret }}
{{- .Values.ai.existingSecret }}
{{- else }}
{{- printf "%s-ai" (include "schnappy.fullname" .) }}
{{- end }}
{{- end }}

{{/*
Webhook secret name
*/}}
{{- define "schnappy.webhook.secretName" -}}
{{- if .Values.webhook.existingSecret }}
{{- .Values.webhook.existingSecret }}
{{- else }}
{{- printf "%s-webhook" (include "schnappy.fullname" .) }}
{{- end }}
{{- end }}

{{/*
Redis secret name
*/}}
{{- define "schnappy.redis.secretName" -}}
{{- if .Values.redis.existingSecret }}
{{- .Values.redis.existingSecret }}
{{- else }}
{{- printf "%s-redis" (include "schnappy.fullname" .) }}
{{- end }}
{{- end }}

{{/*
MinIO secret name
*/}}
{{- define "schnappy.minio.secretName" -}}
{{- if .Values.minio.existingSecret }}
{{- .Values.minio.existingSecret }}
{{- else }}
{{- printf "%s-minio" (include "schnappy.fullname" .) }}
{{- end }}
{{- end }}

{{/*
Redis labels
*/}}
{{- define "schnappy.redis.labels" -}}
{{ include "schnappy.labels" . }}
app.kubernetes.io/component: redis
{{- end }}

{{/*
Redis selector labels
*/}}
{{- define "schnappy.redis.selectorLabels" -}}
{{ include "schnappy.selectorLabels" . }}
app.kubernetes.io/component: redis
{{- end }}

{{/*
Redis service name
*/}}
{{- define "schnappy.redis.serviceName" -}}
{{- printf "%s-redis" (include "schnappy.fullname" .) }}
{{- end }}

{{/*
Frontend labels
*/}}
{{- define "schnappy.site.labels" -}}
{{ include "schnappy.labels" . }}
app.kubernetes.io/component: site
{{- end }}

{{/*
Frontend selector labels
*/}}
{{- define "schnappy.site.selectorLabels" -}}
{{ include "schnappy.selectorLabels" . }}
app.kubernetes.io/component: site
{{- end }}

{{/*
Frontend service name
*/}}
{{- define "schnappy.site.serviceName" -}}
{{- printf "%s-site" (include "schnappy.fullname" .) }}
{{- end }}

{{/*
MinIO labels
*/}}
{{- define "schnappy.minio.labels" -}}
{{ include "schnappy.labels" . }}
app.kubernetes.io/component: minio
{{- end }}

{{/*
MinIO selector labels
*/}}
{{- define "schnappy.minio.selectorLabels" -}}
{{ include "schnappy.selectorLabels" . }}
app.kubernetes.io/component: minio
{{- end }}

{{/*
MinIO service name
*/}}
{{- define "schnappy.minio.serviceName" -}}
{{- printf "%s-minio" (include "schnappy.fullname" .) }}
{{- end }}

{{/*
Elasticsearch labels
*/}}
{{- define "schnappy.elasticsearch.labels" -}}
{{ include "schnappy.labels" . }}
app.kubernetes.io/component: elasticsearch
{{- end }}

{{/*
Elasticsearch selector labels
*/}}
{{- define "schnappy.elasticsearch.selectorLabels" -}}
{{ include "schnappy.selectorLabels" . }}
app.kubernetes.io/component: elasticsearch
{{- end }}

{{/*
Elasticsearch service name
*/}}
{{- define "schnappy.elasticsearch.serviceName" -}}
{{- printf "%s-elasticsearch" (include "schnappy.fullname" .) }}
{{- end }}

{{/*
Elasticsearch secret name
*/}}
{{- define "schnappy.elasticsearch.secretName" -}}
{{- if .Values.elk.elasticsearch.existingSecret }}
{{- .Values.elk.elasticsearch.existingSecret }}
{{- else }}
{{- printf "%s-elasticsearch" (include "schnappy.fullname" .) }}
{{- end }}
{{- end }}

{{/*
Kibana labels
*/}}
{{- define "schnappy.kibana.labels" -}}
{{ include "schnappy.labels" . }}
app.kubernetes.io/component: kibana
{{- end }}

{{/*
Kibana selector labels
*/}}
{{- define "schnappy.kibana.selectorLabels" -}}
{{ include "schnappy.selectorLabels" . }}
app.kubernetes.io/component: kibana
{{- end }}

{{/*
Kibana service name
*/}}
{{- define "schnappy.kibana.serviceName" -}}
{{- printf "%s-kibana" (include "schnappy.fullname" .) }}
{{- end }}

{{/*
Kafka labels
*/}}
{{- define "schnappy.kafka.labels" -}}
{{ include "schnappy.labels" . }}
app.kubernetes.io/component: kafka
{{- end }}

{{/*
Kafka selector labels
*/}}
{{- define "schnappy.kafka.selectorLabels" -}}
{{ include "schnappy.selectorLabels" . }}
app.kubernetes.io/component: kafka
{{- end }}

{{/*
Kafka service name
*/}}
{{- define "schnappy.kafka.serviceName" -}}
{{- printf "%s-kafka" (include "schnappy.fullname" .) }}
{{- end }}

{{/*
Kafka secret name
*/}}
{{- define "schnappy.kafka.secretName" -}}
{{- if .Values.kafka.existingSecret }}
{{- .Values.kafka.existingSecret }}
{{- else }}
{{- printf "%s-kafka" (include "schnappy.fullname" .) }}
{{- end }}
{{- end }}

{{/*
ScyllaDB labels
*/}}
{{- define "schnappy.scylla.labels" -}}
{{ include "schnappy.labels" . }}
app.kubernetes.io/component: scylla
{{- end }}

{{/*
ScyllaDB selector labels
*/}}
{{- define "schnappy.scylla.selectorLabels" -}}
{{ include "schnappy.selectorLabels" . }}
app.kubernetes.io/component: scylla
{{- end }}

{{/*
ScyllaDB service name
*/}}
{{- define "schnappy.scylla.serviceName" -}}
{{- printf "%s-scylla" (include "schnappy.fullname" .) }}
{{- end }}

{{/*
SonarQube labels
*/}}
{{- define "schnappy.sonarqube.labels" -}}
{{ include "schnappy.labels" . }}
app.kubernetes.io/component: sonarqube
{{- end }}

{{/*
SonarQube selector labels
*/}}
{{- define "schnappy.sonarqube.selectorLabels" -}}
{{ include "schnappy.selectorLabels" . }}
app.kubernetes.io/component: sonarqube
{{- end }}

{{/*
SonarQube service name
*/}}
{{- define "schnappy.sonarqube.serviceName" -}}
{{- printf "%s-sonarqube" (include "schnappy.fullname" .) }}
{{- end }}

{{/*
SonarQube secret name
*/}}
{{- define "schnappy.sonarqube.secretName" -}}
{{- if .Values.sonarqube.existingSecret }}
{{- .Values.sonarqube.existingSecret }}
{{- else }}
{{- printf "%s-sonarqube" (include "schnappy.fullname" .) }}
{{- end }}
{{- end }}

{{/*
SonarQube PostgreSQL labels
*/}}
{{- define "schnappy.sonarqube.postgres.labels" -}}
{{ include "schnappy.labels" . }}
app.kubernetes.io/component: sonarqube-postgres
{{- end }}

{{/*
SonarQube PostgreSQL selector labels
*/}}
{{- define "schnappy.sonarqube.postgres.selectorLabels" -}}
{{ include "schnappy.selectorLabels" . }}
app.kubernetes.io/component: sonarqube-postgres
{{- end }}

{{/*
SonarQube PostgreSQL service name
*/}}
{{- define "schnappy.sonarqube.postgres.serviceName" -}}
{{- printf "%s-sonarqube-postgres" (include "schnappy.fullname" .) }}
{{- end }}

{{/*
Fluent-bit labels
*/}}
{{- define "schnappy.fluentbit.labels" -}}
{{ include "schnappy.labels" . }}
app.kubernetes.io/component: fluentbit
{{- end }}

{{/*
Fluent-bit selector labels
*/}}
{{- define "schnappy.fluentbit.selectorLabels" -}}
{{ include "schnappy.selectorLabels" . }}
app.kubernetes.io/component: fluentbit
{{- end }}

{{/*
apt-cache labels
*/}}
{{- define "schnappy.aptCache.labels" -}}
{{ include "schnappy.labels" . }}
app.kubernetes.io/component: apt-cache
{{- end }}

{{/*
apt-cache selector labels
*/}}
{{- define "schnappy.aptCache.selectorLabels" -}}
{{ include "schnappy.selectorLabels" . }}
app.kubernetes.io/component: apt-cache
{{- end }}

{{/*
apt-cache service name
*/}}
{{- define "schnappy.aptCache.serviceName" -}}
{{- printf "%s-apt-cache" (include "schnappy.fullname" .) }}
{{- end }}

{{/*
ES ILM job selector labels (must not overlap with DaemonSet selectors)
*/}}
{{- define "schnappy.esIlmJob.selectorLabels" -}}
{{ include "schnappy.selectorLabels" . }}
app.kubernetes.io/component: es-ilm-job
{{- end }}

{{/*
Admin labels
*/}}
{{- define "schnappy.admin.labels" -}}
{{ include "schnappy.labels" . }}
app.kubernetes.io/component: admin
{{- end }}

{{/*
Admin selector labels
*/}}
{{- define "schnappy.admin.selectorLabels" -}}
{{ include "schnappy.selectorLabels" . }}
app.kubernetes.io/component: admin
{{- end }}

{{/*
Admin service name
*/}}
{{- define "schnappy.admin.serviceName" -}}
{{- printf "%s-admin" (include "schnappy.fullname" .) }}
{{- end }}

{{/*
Chat microservice labels
*/}}
{{- define "schnappy.chat.labels" -}}
{{ include "schnappy.labels" . }}
app.kubernetes.io/component: chat
{{- end }}

{{/*
Chat microservice selector labels
*/}}
{{- define "schnappy.chat.selectorLabels" -}}
{{ include "schnappy.selectorLabels" . }}
app.kubernetes.io/component: chat
{{- end }}

{{/*
Chat microservice service name
*/}}
{{- define "schnappy.chat.serviceName" -}}
{{- printf "%s-chat" (include "schnappy.fullname" .) }}
{{- end }}

{{/*
Chess microservice labels
*/}}
{{- define "schnappy.chess.labels" -}}
{{ include "schnappy.labels" . }}
app.kubernetes.io/component: chess
{{- end }}

{{/*
Chess microservice selector labels
*/}}
{{- define "schnappy.chess.selectorLabels" -}}
{{ include "schnappy.selectorLabels" . }}
app.kubernetes.io/component: chess
{{- end }}

{{/*
Chess microservice service name
*/}}
{{- define "schnappy.chess.serviceName" -}}
{{- printf "%s-chess" (include "schnappy.fullname" .) }}
{{- end }}

{{/*
Gateway labels
*/}}
{{- define "schnappy.gateway.labels" -}}
{{ include "schnappy.labels" . }}
app.kubernetes.io/component: gateway
{{- end }}

{{/*
Gateway selector labels
*/}}
{{- define "schnappy.gateway.selectorLabels" -}}
{{ include "schnappy.selectorLabels" . }}
app.kubernetes.io/component: gateway
{{- end }}

{{/*
Gateway service name
*/}}
{{- define "schnappy.gateway.serviceName" -}}
{{- printf "%s-gateway" (include "schnappy.fullname" .) }}
{{- end }}

{{/*
Alertmanager labels
*/}}
{{- define "schnappy.alertmanager.labels" -}}
{{ include "schnappy.labels" . }}
app.kubernetes.io/component: alertmanager
{{- end }}

{{/*
Alertmanager selector labels
*/}}
{{- define "schnappy.alertmanager.selectorLabels" -}}
{{ include "schnappy.selectorLabels" . }}
app.kubernetes.io/component: alertmanager
{{- end }}

{{/*
Alertmanager service name
*/}}
{{- define "schnappy.alertmanager.serviceName" -}}
{{- printf "%s-alertmanager" (include "schnappy.fullname" .) }}
{{- end }}

{{/*
Alertmanager secret name
*/}}
{{- define "schnappy.alertmanager.secretName" -}}
{{- if .Values.alertmanager.existingSecret }}
{{- .Values.alertmanager.existingSecret }}
{{- else }}
{{- printf "%s-alertmanager" (include "schnappy.fullname" .) }}
{{- end }}
{{- end }}

{{/*
kube-state-metrics labels
*/}}
{{- define "schnappy.kubeStateMetrics.labels" -}}
{{ include "schnappy.labels" . }}
app.kubernetes.io/component: kube-state-metrics
{{- end }}

{{/*
kube-state-metrics selector labels
*/}}
{{- define "schnappy.kubeStateMetrics.selectorLabels" -}}
{{ include "schnappy.selectorLabels" . }}
app.kubernetes.io/component: kube-state-metrics
{{- end }}

{{/*
kube-state-metrics service name
*/}}
{{- define "schnappy.kubeStateMetrics.serviceName" -}}
{{- printf "%s-kube-state-metrics" (include "schnappy.fullname" .) }}
{{- end }}

{{/*
Keycloak labels
*/}}
{{- define "schnappy.keycloak.labels" -}}
{{ include "schnappy.labels" . }}
app.kubernetes.io/component: keycloak
{{- end }}

{{/*
Keycloak selector labels
*/}}
{{- define "schnappy.keycloak.selectorLabels" -}}
{{ include "schnappy.selectorLabels" . }}
app.kubernetes.io/component: keycloak
{{- end }}

{{/*
Keycloak service name
*/}}
{{- define "schnappy.keycloak.serviceName" -}}
{{- printf "%s-keycloak" (include "schnappy.fullname" .) }}
{{- end }}

{{/*
Keycloak secret name
*/}}
{{- define "schnappy.keycloak.secretName" -}}
{{- if .Values.keycloak.existingSecret }}
{{- .Values.keycloak.existingSecret }}
{{- else }}
{{- printf "%s-keycloak" (include "schnappy.fullname" .) }}
{{- end }}
{{- end }}

{{/* Game helpers removed — games are now data-driven via .Values.games list */}}
