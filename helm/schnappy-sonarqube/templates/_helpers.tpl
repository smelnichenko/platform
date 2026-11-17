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

{{/* ========== SonarQube ========== */}}

{{- define "schnappy.sonarqube.labels" -}}
{{ include "schnappy.labels" . }}
app.kubernetes.io/component: sonarqube
{{- end }}

{{- define "schnappy.sonarqube.selectorLabels" -}}
{{ include "schnappy.selectorLabels" . }}
app.kubernetes.io/component: sonarqube
{{- end }}

{{- define "schnappy.sonarqube.serviceName" -}}
{{- printf "%s-sonarqube" (include "schnappy.fullname" .) }}
{{- end }}

{{- define "schnappy.sonarqube.secretName" -}}
{{- if .Values.sonarqube.existingSecret }}
{{- .Values.sonarqube.existingSecret }}
{{- else }}
{{- printf "%s-sonarqube" (include "schnappy.fullname" .) }}
{{- end }}
{{- end }}

{{/* ========== SonarQube PostgreSQL ========== */}}

{{- define "schnappy.sonarqube.postgres.labels" -}}
{{ include "schnappy.labels" . }}
app.kubernetes.io/component: sonarqube-postgres
{{- end }}

{{- define "schnappy.sonarqube.postgres.selectorLabels" -}}
{{ include "schnappy.selectorLabels" . }}
app.kubernetes.io/component: sonarqube-postgres
{{- end }}

{{- define "schnappy.sonarqube.cnpg.name" -}}
{{- printf "%s-sonarqube-pg" (include "schnappy.fullname" .) }}
{{- end }}

{{/* the database SonarQube connects to: CNPG's read-write service, or the StatefulSet's */}}
{{- define "schnappy.sonarqube.database.host" -}}
{{- if eq .Values.sonarqube.database "cnpg" }}
{{- if not (eq (.Values.sonarqube.cnpg.enabled | toString) "true") }}{{ fail "sonarqube.database: cnpg needs sonarqube.cnpg.enabled" }}{{ end }}
{{- printf "%s-rw" (include "schnappy.sonarqube.cnpg.name" .) }}
{{- else if eq .Values.sonarqube.database "statefulset" }}
{{- if eq (int .Values.sonarqube.postgresReplicas) 0 }}{{ fail "sonarqube.database: statefulset needs sonarqube.postgresReplicas above 0" }}{{ end }}
{{- include "schnappy.sonarqube.postgres.serviceName" . }}
{{- else }}
{{- fail (printf "sonarqube.database: cnpg or statefulset, not %q" .Values.sonarqube.database) }}
{{- end }}
{{- end }}

{{- define "schnappy.sonarqube.postgres.serviceName" -}}
{{- printf "%s-sonarqube-postgres" (include "schnappy.fullname" .) }}
{{- end }}
