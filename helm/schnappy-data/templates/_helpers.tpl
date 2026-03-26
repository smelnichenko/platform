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

{{- define "schnappy.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "schnappy.labels" -}}
helm.sh/chart: {{ include "schnappy.chart" . }}
{{ include "schnappy.selectorLabels" . }}
app.kubernetes.io/part-of: schnappy
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "schnappy.selectorLabels" -}}
app.kubernetes.io/name: {{ include "schnappy.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/* ========== PostgreSQL ========== */}}

{{- define "schnappy.postgres.labels" -}}
{{ include "schnappy.labels" . }}
app.kubernetes.io/component: postgres
{{- end }}

{{- define "schnappy.postgres.selectorLabels" -}}
{{ include "schnappy.selectorLabels" . }}
app.kubernetes.io/component: postgres
{{- end }}

{{- define "schnappy.postgres.serviceName" -}}
{{- printf "%s-postgres" (include "schnappy.fullname" .) }}
{{- end }}

{{- define "schnappy.postgres.secretName" -}}
{{- if .Values.postgres.existingSecret }}
{{- .Values.postgres.existingSecret }}
{{- else }}
{{- printf "%s-postgres" (include "schnappy.fullname" .) }}
{{- end }}
{{- end }}

{{/* ========== Redis ========== */}}

{{- define "schnappy.redis.labels" -}}
{{ include "schnappy.labels" . }}
app.kubernetes.io/component: redis
{{- end }}

{{- define "schnappy.redis.selectorLabels" -}}
{{ include "schnappy.selectorLabels" . }}
app.kubernetes.io/component: redis
{{- end }}

{{- define "schnappy.redis.serviceName" -}}
{{- printf "%s-redis" (include "schnappy.fullname" .) }}
{{- end }}

{{- define "schnappy.redis.secretName" -}}
{{- if .Values.redis.existingSecret }}
{{- .Values.redis.existingSecret }}
{{- else }}
{{- printf "%s-redis" (include "schnappy.fullname" .) }}
{{- end }}
{{- end }}

{{/* ========== Kafka ========== */}}

{{- define "schnappy.kafka.labels" -}}
{{ include "schnappy.labels" . }}
app.kubernetes.io/component: kafka
{{- end }}

{{- define "schnappy.kafka.selectorLabels" -}}
{{ include "schnappy.selectorLabels" . }}
app.kubernetes.io/component: kafka
{{- end }}

{{- define "schnappy.kafka.serviceName" -}}
{{- printf "%s-kafka" (include "schnappy.fullname" .) }}
{{- end }}

{{- define "schnappy.kafka.secretName" -}}
{{- if .Values.kafka.existingSecret }}
{{- .Values.kafka.existingSecret }}
{{- else }}
{{- printf "%s-kafka" (include "schnappy.fullname" .) }}
{{- end }}
{{- end }}

{{/* ========== ScyllaDB ========== */}}

{{- define "schnappy.scylla.labels" -}}
{{ include "schnappy.labels" . }}
app.kubernetes.io/component: scylla
{{- end }}

{{- define "schnappy.scylla.selectorLabels" -}}
{{ include "schnappy.selectorLabels" . }}
app.kubernetes.io/component: scylla
{{- end }}

{{- define "schnappy.scylla.serviceName" -}}
{{- printf "%s-scylla" (include "schnappy.fullname" .) }}
{{- end }}

{{/* ========== MinIO ========== */}}

{{- define "schnappy.minio.labels" -}}
{{ include "schnappy.labels" . }}
app.kubernetes.io/component: minio
{{- end }}

{{- define "schnappy.minio.selectorLabels" -}}
{{ include "schnappy.selectorLabels" . }}
app.kubernetes.io/component: minio
{{- end }}

{{- define "schnappy.minio.secretName" -}}
{{- if .Values.minio.existingSecret }}
{{- .Values.minio.existingSecret }}
{{- else }}
{{- printf "%s-minio" (include "schnappy.fullname" .) }}
{{- end }}
{{- end }}

{{/* ========== apt-cache ========== */}}

{{- define "schnappy.aptCache.labels" -}}
{{ include "schnappy.labels" . }}
app.kubernetes.io/component: apt-cache
{{- end }}

{{- define "schnappy.aptCache.selectorLabels" -}}
{{ include "schnappy.selectorLabels" . }}
app.kubernetes.io/component: apt-cache
{{- end }}

{{/* ========== Cross-chart selector labels (for NPs referencing pods in other charts) ========== */}}

{{- define "schnappy.monitor.selectorLabels" -}}
{{ include "schnappy.selectorLabels" . }}
app.kubernetes.io/component: app
{{- end }}

{{- define "schnappy.admin.selectorLabels" -}}
{{ include "schnappy.selectorLabels" . }}
app.kubernetes.io/component: admin
{{- end }}

{{- define "schnappy.chat.selectorLabels" -}}
{{ include "schnappy.selectorLabels" . }}
app.kubernetes.io/component: chat
{{- end }}

{{- define "schnappy.chess.selectorLabels" -}}
{{ include "schnappy.selectorLabels" . }}
app.kubernetes.io/component: chess
{{- end }}

{{- define "schnappy.gateway.selectorLabels" -}}
{{ include "schnappy.selectorLabels" . }}
app.kubernetes.io/component: gateway
{{- end }}

{{- define "schnappy.keycloak.selectorLabels" -}}
{{ include "schnappy.selectorLabels" . }}
app.kubernetes.io/component: keycloak
{{- end }}
