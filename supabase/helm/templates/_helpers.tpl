{{/*
Expand the name of the chart.
*/}}
{{- define "supabase.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "supabase.fullname" -}}
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
{{- define "supabase.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
Multi-service chart: `app.kubernetes.io/component` is set per-template
(postgres, postgrest, auth, realtime, meta, studio, caddy) via `supabase.componentLabels`.
*/}}
{{- define "supabase.labels" -}}
helm.sh/chart: {{ include "supabase.chart" . }}
{{ include "supabase.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: weown-mvp
{{- end }}

{{/*
Per-service component labels — call with a dict:
{{ include "supabase.componentLabels" (dict "root" . "component" "postgres") }}
*/}}
{{- define "supabase.componentLabels" -}}
{{ include "supabase.labels" .root }}
app.kubernetes.io/component: {{ .component }}
supabase.io/service: {{ .component }}
{{- end }}

{{/*
Labels for backup resources
*/}}
{{- define "supabase.backupLabels" -}}
{{ include "supabase.labels" . }}
app.kubernetes.io/component: backup
{{- end }}

{{/*
Selector labels
Per-service selectors add `supabase.io/service` to disambiguate pods per service.
*/}}
{{- define "supabase.selectorLabels" -}}
app.kubernetes.io/name: {{ include "supabase.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Per-service selector labels — call with a dict:
{{ include "supabase.componentSelectorLabels" (dict "root" . "component" "postgres") }}
*/}}
{{- define "supabase.componentSelectorLabels" -}}
{{ include "supabase.selectorLabels" .root }}
supabase.io/service: {{ .component }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "supabase.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "supabase.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}
