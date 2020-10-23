{{/*
Expand the name of the chart.
*/}}
{{- define "alchemist-web.name" -}}
{{- default .Chart.Name .Values.deployment.webapp.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "alchemist-web.fullname" -}}
{{- if .Values.deployment.webapp.fullnameOverride }}
{{- .Values.deployment.webapp.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.deployment.webapp.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s" $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "alchemist-web.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "alchemist-web.labels" -}}
helm.sh/chart: {{ include "alchemist-web.chart" . }}
{{ include "alchemist-web.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "alchemist-web.selectorLabels" -}}
app.kubernetes.io/name: {{ include "alchemist-web.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "alchemist-web.serviceAccountName" -}}
{{- if .Values.deployment.webapp.serviceAccount.create }}
{{- default (include "alchemist-web.fullname" .) .Values.deployment.webapp.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.deployment.webapp.serviceAccount.name }}
{{- end }}
{{- end }}
