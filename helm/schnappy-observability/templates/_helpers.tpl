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

{{/* ========== ClickHouse (logs) ========== */}}

{{- define "schnappy.clickhouse.labels" -}}
{{ include "schnappy.labels" . }}
app.kubernetes.io/component: clickhouse
{{- end }}

{{- define "schnappy.clickhouse.selectorLabels" -}}
{{ include "schnappy.selectorLabels" . }}
app.kubernetes.io/component: clickhouse
{{- end }}

{{- define "schnappy.clickhouse.serviceName" -}}
{{- printf "%s-clickhouse" (include "schnappy.fullname" .) }}
{{- end }}

{{- define "schnappy.clickhouse.secretName" -}}
{{- with .Values.clickhouse }}
{{- if .existingSecret }}
{{- .existingSecret }}
{{- else }}
{{- printf "%s-clickhouse" (include "schnappy.fullname" $) }}
{{- end }}
{{- end }}
{{- end }}

{{/* ========== Fluent-bit ========== */}}

{{- define "schnappy.fluentbit.labels" -}}
{{ include "schnappy.labels" . }}
app.kubernetes.io/component: fluentbit
{{- end }}

{{- define "schnappy.fluentbit.selectorLabels" -}}
{{ include "schnappy.selectorLabels" . }}
app.kubernetes.io/component: fluentbit
{{- end }}

{{/* ========== Mimir ========== */}}

{{- define "schnappy.mimir.labels" -}}
{{ include "schnappy.labels" . }}
app.kubernetes.io/component: mimir
{{- end }}

{{- define "schnappy.mimir.selectorLabels" -}}
{{ include "schnappy.selectorLabels" . }}
app.kubernetes.io/component: mimir
{{- end }}

{{- define "schnappy.mimir.serviceName" -}}
{{- printf "%s-mimir" (include "schnappy.fullname" .) }}
{{- end }}

{{/* ========== Tempo ========== */}}

{{- define "schnappy.tempo.labels" -}}
{{ include "schnappy.labels" . }}
app.kubernetes.io/component: tempo
{{- end }}

{{- define "schnappy.tempo.selectorLabels" -}}
{{ include "schnappy.selectorLabels" . }}
app.kubernetes.io/component: tempo
{{- end }}

{{- define "schnappy.tempo.serviceName" -}}
{{- printf "%s-tempo" (include "schnappy.fullname" .) }}
{{- end }}

{{/* ========== Grafana ========== */}}

{{- define "schnappy.grafana.labels" -}}
{{ include "schnappy.labels" . }}
app.kubernetes.io/component: grafana
{{- end }}

{{- define "schnappy.grafana.selectorLabels" -}}
{{ include "schnappy.selectorLabels" . }}
app.kubernetes.io/component: grafana
{{- end }}

{{- define "schnappy.grafana.secretName" -}}
{{- if .Values.grafana.existingSecret }}
{{- .Values.grafana.existingSecret }}
{{- else }}
{{- printf "%s-grafana" (include "schnappy.fullname" .) }}
{{- end }}
{{- end }}

{{/* ========== Alertmanager ========== */}}

{{- define "schnappy.alertmanager.labels" -}}
{{ include "schnappy.labels" . }}
app.kubernetes.io/component: alertmanager
{{- end }}

{{- define "schnappy.alertmanager.selectorLabels" -}}
{{ include "schnappy.selectorLabels" . }}
app.kubernetes.io/component: alertmanager
{{- end }}

{{- define "schnappy.alertmanager.serviceName" -}}
{{- printf "%s-alertmanager" (include "schnappy.fullname" .) }}
{{- end }}

{{- define "schnappy.alertmanager.secretName" -}}
{{- if .Values.alertmanager.existingSecret }}
{{- .Values.alertmanager.existingSecret }}
{{- else }}
{{- printf "%s-alertmanager" (include "schnappy.fullname" .) }}
{{- end }}
{{- end }}

{{/* ========== kube-state-metrics ========== */}}

{{- define "schnappy.kubeStateMetrics.labels" -}}
{{ include "schnappy.labels" . }}
app.kubernetes.io/component: kube-state-metrics
{{- end }}

{{- define "schnappy.kubeStateMetrics.selectorLabels" -}}
{{ include "schnappy.selectorLabels" . }}
app.kubernetes.io/component: kube-state-metrics
{{- end }}

{{- define "schnappy.kubeStateMetrics.serviceName" -}}
{{- printf "%s-kube-state-metrics" (include "schnappy.fullname" .) }}
{{- end }}

{{/* ========== Reports ========== */}}

{{- define "schnappy.reports.labels" -}}
{{ include "schnappy.labels" . }}
app.kubernetes.io/component: reports
{{- end }}

{{- define "schnappy.reports.selectorLabels" -}}
{{ include "schnappy.selectorLabels" . }}
app.kubernetes.io/component: reports
{{- end }}

{{- define "schnappy.runbooks.labels" -}}
{{ include "schnappy.labels" . }}
app.kubernetes.io/component: runbooks
{{- end }}

{{- define "schnappy.runbooks.selectorLabels" -}}
{{ include "schnappy.selectorLabels" . }}
app.kubernetes.io/component: runbooks
{{- end }}

{{/* ========== Cross-chart service name helpers ========== */}}

{{- define "schnappy.monitor.serviceName" -}}
{{- printf "%s-monitor" (include "schnappy.fullname" .) }}
{{- end }}

{{/* ========== Cross-chart selector labels (for NPs referencing pods in other charts) ========== */}}

{{- define "schnappy.monitor.selectorLabels" -}}
{{ include "schnappy.selectorLabels" . }}
app.kubernetes.io/component: monitor
{{- end }}

{{- define "schnappy.keycloak.selectorLabels" -}}
{{ include "schnappy.selectorLabels" . }}
app.kubernetes.io/component: keycloak
{{- end }}
