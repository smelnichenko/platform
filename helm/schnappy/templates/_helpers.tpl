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
app.kubernetes.io/part-of: schnappy
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

{{/* ========== App (core backend) ========== */}}

{{- define "schnappy.monitor.labels" -}}
{{ include "schnappy.labels" . }}
app.kubernetes.io/component: app
{{- end }}

{{- define "schnappy.monitor.selectorLabels" -}}
{{ include "schnappy.selectorLabels" . }}
app.kubernetes.io/component: app
{{- end }}

{{- define "schnappy.monitor.serviceName" -}}
{{- printf "%s-monitor" (include "schnappy.fullname" .) }}
{{- end }}

{{/* ========== Site (frontend) ========== */}}

{{- define "schnappy.site.labels" -}}
{{ include "schnappy.labels" . }}
app.kubernetes.io/component: site
{{- end }}

{{- define "schnappy.site.selectorLabels" -}}
{{ include "schnappy.selectorLabels" . }}
app.kubernetes.io/component: site
{{- end }}

{{- define "schnappy.site.serviceName" -}}
{{- printf "%s-site" (include "schnappy.fullname" .) }}
{{- end }}

{{/* ========== Admin ========== */}}

{{- define "schnappy.admin.labels" -}}
{{ include "schnappy.labels" . }}
app.kubernetes.io/component: admin
{{- end }}

{{- define "schnappy.admin.selectorLabels" -}}
{{ include "schnappy.selectorLabels" . }}
app.kubernetes.io/component: admin
{{- end }}

{{- define "schnappy.admin.serviceName" -}}
{{- printf "%s-admin" (include "schnappy.fullname" .) }}
{{- end }}

{{/* ========== Chat ========== */}}

{{- define "schnappy.chat.labels" -}}
{{ include "schnappy.labels" . }}
app.kubernetes.io/component: chat
{{- end }}

{{- define "schnappy.chat.selectorLabels" -}}
{{ include "schnappy.selectorLabels" . }}
app.kubernetes.io/component: chat
{{- end }}

{{- define "schnappy.chat.serviceName" -}}
{{- printf "%s-chat" (include "schnappy.fullname" .) }}
{{- end }}

{{/* ========== Chess ========== */}}

{{- define "schnappy.chess.labels" -}}
{{ include "schnappy.labels" . }}
app.kubernetes.io/component: chess
{{- end }}

{{- define "schnappy.chess.selectorLabels" -}}
{{ include "schnappy.selectorLabels" . }}
app.kubernetes.io/component: chess
{{- end }}

{{- define "schnappy.chess.serviceName" -}}
{{- printf "%s-chess" (include "schnappy.fullname" .) }}
{{- end }}

{{/* ========== Gateway ========== */}}

{{- define "schnappy.gateway.labels" -}}
{{ include "schnappy.labels" . }}
app.kubernetes.io/component: gateway
{{- end }}

{{- define "schnappy.gateway.selectorLabels" -}}
{{ include "schnappy.selectorLabels" . }}
app.kubernetes.io/component: gateway
{{- end }}

{{- define "schnappy.gateway.serviceName" -}}
{{- printf "%s-gateway" (include "schnappy.fullname" .) }}
{{- end }}

{{/* ========== Secret name helpers (cross-chart references) ========== */}}

{{- define "schnappy.postgres.secretName" -}}
{{- if .Values.postgres }}
{{- if .Values.postgres.existingSecret }}
{{- .Values.postgres.existingSecret }}
{{- else }}
{{- printf "%s-postgres" (include "schnappy.fullname" .) }}
{{- end }}
{{- else }}
{{- printf "%s-postgres" (include "schnappy.fullname" .) }}
{{- end }}
{{- end }}

{{- define "schnappy.redis.secretName" -}}
{{- if .Values.redis }}
{{- if .Values.redis.existingSecret }}
{{- .Values.redis.existingSecret }}
{{- else }}
{{- printf "%s-redis" (include "schnappy.fullname" .) }}
{{- end }}
{{- else }}
{{- printf "%s-redis" (include "schnappy.fullname" .) }}
{{- end }}
{{- end }}

{{- define "schnappy.ai.secretName" -}}
{{- if .Values.ai.existingSecret }}
{{- .Values.ai.existingSecret }}
{{- else }}
{{- printf "%s-ai" (include "schnappy.fullname" .) }}
{{- end }}
{{- end }}

{{- define "schnappy.mail.secretName" -}}
{{- if .Values.mail.existingSecret }}
{{- .Values.mail.existingSecret }}
{{- else }}
{{- printf "%s-mail" (include "schnappy.fullname" .) }}
{{- end }}
{{- end }}

{{- define "schnappy.webhook.secretName" -}}
{{- if .Values.webhook.existingSecret }}
{{- .Values.webhook.existingSecret }}
{{- else }}
{{- printf "%s-webhook" (include "schnappy.fullname" .) }}
{{- end }}
{{- end }}

{{- define "schnappy.minio.secretName" -}}
{{- if .Values.minio }}
{{- if .Values.minio.existingSecret }}
{{- .Values.minio.existingSecret }}
{{- else }}
{{- printf "%s-minio" (include "schnappy.fullname" .) }}
{{- end }}
{{- else }}
{{- printf "%s-minio" (include "schnappy.fullname" .) }}
{{- end }}
{{- end }}

{{- define "schnappy.kafka.serviceName" -}}
{{- printf "%s-kafka" (include "schnappy.fullname" .) }}
{{- end }}

{{- define "schnappy.scylla.serviceName" -}}
{{- printf "%s-scylla" (include "schnappy.fullname" .) }}
{{- end }}

{{/* Cross-chart service name helpers */}}

{{- define "schnappy.postgres.serviceName" -}}
{{- printf "%s-postgres" (include "schnappy.fullname" .) }}
{{- end }}

{{- define "schnappy.redis.serviceName" -}}
{{- printf "%s-redis" (include "schnappy.fullname" .) }}
{{- end }}

{{- define "schnappy.keycloak.serviceName" -}}
{{- printf "%s-keycloak" (include "schnappy.fullname" .) }}
{{- end }}

{{- define "schnappy.victoriametrics.serviceName" -}}
{{- printf "%s-victoriametrics" (include "schnappy.fullname" .) }}
{{- end }}

{{- define "schnappy.keycloak.secretName" -}}
{{- if .Values.keycloak }}
{{- if .Values.keycloak.existingSecret }}
{{- .Values.keycloak.existingSecret }}
{{- else }}
{{- printf "%s-keycloak" (include "schnappy.fullname" .) }}
{{- end }}
{{- else }}
{{- printf "%s-keycloak" (include "schnappy.fullname" .) }}
{{- end }}
{{- end }}

{{/* Cross-chart selector labels (for NPs referencing pods in other charts) */}}

{{- define "schnappy.postgres.selectorLabels" -}}
{{ include "schnappy.selectorLabels" . }}
app.kubernetes.io/component: postgres
{{- end }}

{{- define "schnappy.redis.selectorLabels" -}}
{{ include "schnappy.selectorLabels" . }}
app.kubernetes.io/component: redis
{{- end }}

{{- define "schnappy.kafka.selectorLabels" -}}
{{ include "schnappy.selectorLabels" . }}
app.kubernetes.io/component: kafka
{{- end }}

{{- define "schnappy.scylla.selectorLabels" -}}
{{ include "schnappy.selectorLabels" . }}
app.kubernetes.io/component: scylla
{{- end }}

{{- define "schnappy.minio.selectorLabels" -}}
{{ include "schnappy.selectorLabels" . }}
app.kubernetes.io/component: minio
{{- end }}

{{- define "schnappy.elasticsearch.selectorLabels" -}}
{{ include "schnappy.selectorLabels" . }}
app.kubernetes.io/component: elasticsearch
{{- end }}

{{- define "schnappy.keycloak.selectorLabels" -}}
{{ include "schnappy.selectorLabels" . }}
app.kubernetes.io/component: keycloak
{{- end }}

{{- define "schnappy.victoriametrics.selectorLabels" -}}
{{ include "schnappy.selectorLabels" . }}
app.kubernetes.io/component: victoriametrics
{{- end }}

{{- define "schnappy.alertmanager.selectorLabels" -}}
{{ include "schnappy.selectorLabels" . }}
app.kubernetes.io/component: alertmanager
{{- end }}

{{- define "schnappy.alertmanager.secretName" -}}
{{- if .Values.alertmanager }}
{{- if .Values.alertmanager.existingSecret }}
{{- .Values.alertmanager.existingSecret }}
{{- else }}
{{- printf "%s-alertmanager" (include "schnappy.fullname" .) }}
{{- end }}
{{- else }}
{{- printf "%s-alertmanager" (include "schnappy.fullname" .) }}
{{- end }}
{{- end }}
