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

{{/* ========== Keycloak ========== */}}

{{- define "schnappy.keycloak.labels" -}}
{{ include "schnappy.labels" . }}
app.kubernetes.io/component: keycloak
{{- end }}

{{- define "schnappy.keycloak.selectorLabels" -}}
{{ include "schnappy.selectorLabels" . }}
app.kubernetes.io/component: keycloak
{{- end }}

{{- define "schnappy.keycloak.serviceName" -}}
{{- printf "%s-keycloak" (include "schnappy.fullname" .) }}
{{- end }}

{{- define "schnappy.keycloak.secretName" -}}
{{- if .Values.keycloak.existingSecret }}
{{- .Values.keycloak.existingSecret }}
{{- else }}
{{- printf "%s-keycloak" (include "schnappy.fullname" .) }}
{{- end }}
{{- end }}

{{/* Cross-chart secret refs */}}

{{- define "schnappy.mail.secretName" -}}
{{- if .Values.mail }}
{{- if .Values.mail.existingSecret }}
{{- .Values.mail.existingSecret }}
{{- else }}
{{- printf "%s-mail" (include "schnappy.fullname" .) }}
{{- end }}
{{- else }}
{{- printf "%s-mail" (include "schnappy.fullname" .) }}
{{- end }}
{{- end }}

{{- define "schnappy.postgres.serviceName" -}}
{{- printf "%s-postgres" (include "schnappy.fullname" .) }}
{{- end }}

{{/* Cross-chart selector labels (for NPs referencing pods in other charts) */}}

{{- define "schnappy.monitor.selectorLabels" -}}
{{ include "schnappy.selectorLabels" . }}
app.kubernetes.io/component: app
{{- end }}

{{- define "schnappy.gateway.selectorLabels" -}}
{{ include "schnappy.selectorLabels" . }}
app.kubernetes.io/component: gateway
{{- end }}

{{- define "schnappy.admin.selectorLabels" -}}
{{ include "schnappy.selectorLabels" . }}
app.kubernetes.io/component: admin
{{- end }}

{{- define "schnappy.grafana.selectorLabels" -}}
{{ include "schnappy.selectorLabels" . }}
app.kubernetes.io/component: grafana
{{- end }}

{{- define "schnappy.grafana.secretName" -}}
{{- if .Values.grafana }}
{{- if .Values.grafana.existingSecret }}
{{- .Values.grafana.existingSecret }}
{{- else }}
{{- printf "%s-grafana" (include "schnappy.fullname" .) }}
{{- end }}
{{- else }}
{{- printf "%s-grafana" (include "schnappy.fullname" .) }}
{{- end }}
{{- end }}

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

{{- define "schnappy.postgres.selectorLabels" -}}
{{ include "schnappy.selectorLabels" . }}
app.kubernetes.io/component: postgres
{{- end }}
