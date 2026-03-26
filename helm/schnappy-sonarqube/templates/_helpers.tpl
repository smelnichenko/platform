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

{{- define "schnappy.sonarqube.postgres.serviceName" -}}
{{- printf "%s-sonarqube-postgres" (include "schnappy.fullname" .) }}
{{- end }}
