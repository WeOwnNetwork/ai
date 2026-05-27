{{/*
Expand the name of the chart.
*/}}
{{- define "cluster-backup.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "cluster-backup.fullname" -}}
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
{{- define "cluster-backup.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels.
Every per-resource template adds its OWN `app.kubernetes.io/component`
right below the include of this helper (velero-server, restic,
backup-system, etc.), so we intentionally do NOT set
`app.kubernetes.io/component` here. Doing so produces a YAML
duplicate-key — silently tolerated by the K8s API server (last write
wins) but rejected by strict YAML parsers including `kubeconform`.
*/}}
{{- define "cluster-backup.labels" -}}
helm.sh/chart: {{ include "cluster-backup.chart" . }}
{{ include "cluster-backup.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: weown-cluster-backup
{{- end }}

{{/*
Selector labels
*/}}
{{- define "cluster-backup.selectorLabels" -}}
app.kubernetes.io/name: {{ include "cluster-backup.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Velero server ServiceAccount name.
The chart unconditionally creates this ServiceAccount (templates/velero-serviceaccount.yaml)
and the matching ClusterRoleBinding (templates/velero-rbac.yaml).
*/}}
{{- define "cluster-backup.serviceAccountName" -}}
{{- printf "%s-velero" (include "cluster-backup.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Restic (node-agent) ServiceAccount name.
The chart unconditionally creates this ServiceAccount when restic is enabled.
*/}}
{{- define "cluster-backup.resticServiceAccountName" -}}
{{- printf "%s-restic" (include "cluster-backup.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create backup storage location name
*/}}
{{- define "cluster-backup.backupStorageLocationName" -}}
{{- printf "%s-backup-location" (include "cluster-backup.fullname" .) }}
{{- end }}

{{/*
Create volume snapshot location name
*/}}
{{- define "cluster-backup.volumeSnapshotLocationName" -}}
{{- printf "%s-volume-snapshot-location" (include "cluster-backup.fullname" .) }}
{{- end }}

{{/*
Create backup schedule name
*/}}
{{- define "cluster-backup.backupScheduleName" -}}
{{- $name := .name | default "backup" }}
{{- printf "%s-%s-schedule" (include "cluster-backup.fullname" $) $name }}
{{- end }}

{{/*
Create restore name
*/}}
{{- define "cluster-backup.restoreName" -}}
{{- $name := .name | default "restore" }}
{{- printf "%s-%s-restore" (include "cluster-backup.fullname" $) $name }}
{{- end }}

{{/*
Generate backup storage location configuration
*/}}
{{- define "cluster-backup.backupStorageLocationConfig" -}}
provider: {{ .Values.backupStorage.provider }}
bucket: {{ .Values.backupStorage.bucket }}
config:
  region: {{ .Values.backupStorage.region }}
  s3Url: {{ .Values.backupStorage.s3Url }}
  s3ForcePathStyle: {{ .Values.backupStorage.s3ForcePathStyle | quote }}
  {{- if .Values.backupStorage.encryption.enabled }}
  serverSideEncryption: AES256
  {{- if .Values.backupStorage.encryption.keyId }}
  kmsKeyId: {{ .Values.backupStorage.encryption.keyId }}
  {{- end }}
  {{- end }}
{{- end }}

{{/*
Generate volume snapshot location configuration
*/}}
{{- define "cluster-backup.volumeSnapshotLocationConfig" -}}
provider: {{ .Values.backupStorage.provider }}
config:
  region: {{ .Values.backupStorage.region }}
  {{- if .Values.backupStorage.encryption.enabled }}
  serverSideEncryption: AES256
  {{- if .Values.backupStorage.encryption.keyId }}
  kmsKeyId: {{ .Values.backupStorage.encryption.keyId }}
  {{- end }}
  {{- end }}
{{- end }}

{{/*
Generate backup schedule configuration.

Expected context (passed by templates/backup-schedules.yaml):
  .Chart, .Release, .Values, .Template — chart-root (so the helper can
    call `cluster-backup.fullname` / `cluster-backup.labels` / etc.)
  .name      — string name of this schedule (e.g. "daily", "wordpress")
  .schedule  — the full schedule map from values.yaml, with fields
               .schedule (cron), .retention (TTL), .includeNamespaces,
               .excludeNamespaces.

The previous form accessed `.schedule | quote` at the top level, which
rendered the WHOLE schedule object as a Go-formatted "map[…]" string
instead of the cron expression — a long-standing bug in this chart.
*/}}
{{- define "cluster-backup.backupScheduleConfig" -}}
schedule: {{ .schedule.schedule | quote }}
template:
  metadata:
    labels:
      {{- include "cluster-backup.labels" . | nindent 6 }}
      app.kubernetes.io/component: backup-schedule
  spec:
    storageLocation: {{ include "cluster-backup.backupStorageLocationName" . }}
    volumeSnapshotLocations:
      - {{ include "cluster-backup.volumeSnapshotLocationName" . }}
    {{- if .schedule.includeNamespaces }}
    includedNamespaces:
      {{- range .schedule.includeNamespaces }}
      - {{ . }}
      {{- end }}
    {{- end }}
    {{- if .schedule.excludeNamespaces }}
    excludedNamespaces:
      {{- range .schedule.excludeNamespaces }}
      - {{ . }}
      {{- end }}
    {{- end }}
    ttl: {{ .schedule.retention | quote }}
    {{- if .Values.velero.restic.enabled }}
    defaultVolumesToRestic: true
    {{- end }}
{{- end }}

{{/*
Generate restore configuration
*/}}
{{- define "cluster-backup.restoreConfig" -}}
backupName: {{ .backupName | quote }}
{{- if .includeNamespaces }}
includedNamespaces:
  {{- range .includeNamespaces }}
  - {{ . }}
  {{- end }}
{{- end }}
{{- if .excludeNamespaces }}
excludedNamespaces:
  {{- range .excludeNamespaces }}
  - {{ . }}
  {{- end }}
{{- end }}
{{- if .namespaceMapping }}
namespaceMapping:
  {{- range $old, $new := .namespaceMapping }}
  {{ $old }}: {{ $new }}
  {{- end }}
{{- end }}
{{- if .restorePVs }}
restorePVs: {{ .restorePVs }}
{{- end }}
{{- end }}

{{/*
Generate tenant identifier
*/}}
{{- define "cluster-backup.tenantId" -}}
{{- printf "%s-%s-%s" .Values.global.tenant .Values.global.cluster .Values.global.environment }}
{{- end }}

{{/*
Generate backup retention policy
*/}}
{{- define "cluster-backup.retentionPolicy" -}}
{{- $retention := .retention | default "30d" }}
{{- if hasSuffix "d" $retention }}
{{- $days := trimSuffix "d" $retention | int }}
{{- printf "%dh" (mul $days 24) }}
{{- else if hasSuffix "h" $retention }}
{{- $retention }}
{{- else if hasSuffix "m" $retention }}
{{- $retention }}
{{- else }}
{{- printf "%s" $retention }}
{{- end }}
{{- end }}

{{/*
Generate backup schedule cron expression
*/}}
{{- define "cluster-backup.cronExpression" -}}
{{- $schedule := .schedule | default "0 2 * * *" }}
{{- if hasPrefix "0 " $schedule }}
{{- $schedule }}
{{- else }}
{{- printf "0 %s" $schedule }}
{{- end }}
{{- end }}

{{/*
Generate backup labels
*/}}
{{- define "cluster-backup.backupLabels" -}}
{{- include "cluster-backup.labels" . }}
app.kubernetes.io/component: backup
backup.weown.xyz/tenant: {{ .Values.global.tenant }}
backup.weown.xyz/cluster: {{ .Values.global.cluster }}
backup.weown.xyz/environment: {{ .Values.global.environment }}
{{- end }}

{{/*
Generate restore labels
*/}}
{{- define "cluster-backup.restoreLabels" -}}
{{- include "cluster-backup.labels" . }}
app.kubernetes.io/component: restore
restore.weown.xyz/tenant: {{ .Values.global.tenant }}
restore.weown.xyz/cluster: {{ .Values.global.cluster }}
restore.weown.xyz/environment: {{ .Values.global.environment }}
{{- end }}

{{/*
Generate backup schedule labels
*/}}
{{- define "cluster-backup.scheduleLabels" -}}
{{- include "cluster-backup.labels" . }}
app.kubernetes.io/component: backup-schedule
schedule.weown.xyz/tenant: {{ .Values.global.tenant }}
schedule.weown.xyz/cluster: {{ .Values.global.cluster }}
schedule.weown.xyz/environment: {{ .Values.global.environment }}
{{- end }}

{{/*
Generate backup storage location labels
*/}}
{{- define "cluster-backup.storageLocationLabels" -}}
{{- include "cluster-backup.labels" . }}
app.kubernetes.io/component: backup-storage
storage.weown.xyz/tenant: {{ .Values.global.tenant }}
storage.weown.xyz/cluster: {{ .Values.global.cluster }}
storage.weown.xyz/environment: {{ .Values.global.environment }}
{{- end }}

{{/*
Generate volume snapshot location labels
*/}}
{{- define "cluster-backup.volumeSnapshotLabels" -}}
{{- include "cluster-backup.labels" . }}
app.kubernetes.io/component: volume-snapshot
snapshot.weown.xyz/tenant: {{ .Values.global.tenant }}
snapshot.weown.xyz/cluster: {{ .Values.global.cluster }}
snapshot.weown.xyz/environment: {{ .Values.global.environment }}
{{- end }}
