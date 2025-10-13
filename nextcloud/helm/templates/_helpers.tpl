{{/*
Expand the name of the chart.
*/}}
{{- define "nextcloud.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "nextcloud.fullname" -}}
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
{{- define "nextcloud.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "nextcloud.labels" -}}
helm.sh/chart: {{ include "nextcloud.chart" . }}
{{ include "nextcloud.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "nextcloud.selectorLabels" -}}
app.kubernetes.io/name: {{ include "nextcloud.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "nextcloud.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "nextcloud.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Nextcloud labels
*/}}
{{- define "nextcloud.nextcloudLabels" -}}
app.kubernetes.io/name: {{ include "nextcloud.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: nextcloud
{{- end }}

{{/*
PostgreSQL labels
*/}}
{{- define "nextcloud.postgresqlLabels" -}}
app.kubernetes.io/name: postgresql
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: database
{{- end }}

{{/*
Redis labels
*/}}
{{- define "nextcloud.redisLabels" -}}
app.kubernetes.io/name: redis
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: cache
{{- end }}

{{/*
Create the name of the Nextcloud service
*/}}
{{- define "nextcloud.serviceName" -}}
{{- include "nextcloud.fullname" . }}
{{- end }}

{{/*
Create the name of the PostgreSQL service
*/}}
{{- define "nextcloud.postgresqlServiceName" -}}
{{- printf "%s-postgresql" (include "nextcloud.fullname" .) }}
{{- end }}

{{/*
Create the name of the Redis service
*/}}
{{- define "nextcloud.redisServiceName" -}}
{{- printf "%s-redis" (include "nextcloud.fullname" .) }}
{{- end }}

{{/*
Create the name of the Nextcloud secret
*/}}
{{- define "nextcloud.secretName" -}}
{{- include "nextcloud.fullname" . }}
{{- end }}

{{/*
Create the name of the PostgreSQL secret
*/}}
{{- define "nextcloud.postgresqlSecretName" -}}
{{- printf "%s-postgresql" (include "nextcloud.fullname" .) }}
{{- end }}

{{/*
Create the name of the Redis secret
*/}}
{{- define "nextcloud.redisSecretName" -}}
{{- printf "%s-redis" (include "nextcloud.fullname" .) }}
{{- end }}

{{/*
Create the name of the Nextcloud configmap
*/}}
{{- define "nextcloud.configMapName" -}}
{{- printf "%s-config" (include "nextcloud.fullname" .) }}
{{- end }}

{{/*
Create the name of the Nextcloud data PVC
*/}}
{{- define "nextcloud.dataPVCName" -}}
{{- printf "%s-data" (include "nextcloud.fullname" .) }}
{{- end }}

{{/*
Create the name of the Nextcloud config PVC
*/}}
{{- define "nextcloud.configPVCName" -}}
{{- printf "%s-config" (include "nextcloud.fullname" .) }}
{{- end }}

{{/*
Create the name of the Nextcloud apps PVC
*/}}
{{- define "nextcloud.appsPVCName" -}}
{{- printf "%s-apps" (include "nextcloud.fullname" .) }}
{{- end }}

{{/*
Create the name of the PostgreSQL PVC
*/}}
{{- define "nextcloud.postgresqlPVCName" -}}
{{- printf "%s-postgresql" (include "nextcloud.fullname" .) }}
{{- end }}

{{/*
Create the name of the backup PVC
*/}}
{{- define "nextcloud.backupPVCName" -}}
{{- printf "%s-backup" (include "nextcloud.fullname" .) }}
{{- end }}

{{/*
Create the name of the Nextcloud ingress
*/}}
{{- define "nextcloud.ingressName" -}}
{{- include "nextcloud.fullname" . }}
{{- end }}

{{/*
Create the name of the Nextcloud network policy
*/}}
{{- define "nextcloud.networkPolicyName" -}}
{{- include "nextcloud.fullname" . }}
{{- end }}

{{/*
Create the name of the Nextcloud HPA
*/}}
{{- define "nextcloud.hpaName" -}}
{{- include "nextcloud.fullname" . }}
{{- end }}

{{/*
Create the name of the Nextcloud PDB
*/}}
{{- define "nextcloud.pdbName" -}}
{{- include "nextcloud.fullname" . }}
{{- end }}

{{/*
Create the name of the Nextcloud cron job
*/}}
{{- define "nextcloud.cronJobName" -}}
{{- printf "%s-cron" (include "nextcloud.fullname" .) }}
{{- end }}

{{/*
Create the name of the backup cron job
*/}}
{{- define "nextcloud.backupCronJobName" -}}
{{- printf "%s-backup" (include "nextcloud.fullname" .) }}
{{- end }}

{{/*
Create the name of the ClusterIssuer
*/}}
{{- define "nextcloud.clusterIssuerName" -}}
letsencrypt-prod
{{- end }}

{{/*
Create the domain name
*/}}
{{- define "nextcloud.domain" -}}
{{- .Values.global.domain }}
{{- end }}

{{/*
Create the email for certificates
*/}}
{{- define "nextcloud.email" -}}
{{- .Values.global.email }}
{{- end }}

{{/*
Create the namespace
*/}}
{{- define "nextcloud.namespace" -}}
{{- .Release.Namespace }}
{{- end }}

{{/*
Create the release name
*/}}
{{- define "nextcloud.releaseName" -}}
{{- .Release.Name }}
{{- end }}

{{/*
Create the image repository
*/}}
{{- define "nextcloud.imageRepository" -}}
{{- if .Values.global.imageRegistry }}
{{- printf "%s/%s" .Values.global.imageRegistry .Values.nextcloud.image.repository }}
{{- else }}
{{- .Values.nextcloud.image.repository }}
{{- end }}
{{- end }}

{{/*
Create the PostgreSQL image repository
*/}}
{{- define "nextcloud.postgresqlImageRepository" -}}
{{- if .Values.global.imageRegistry }}
{{- printf "%s/%s" .Values.global.imageRegistry .Values.postgresql.image }}
{{- else }}
{{- .Values.postgresql.image }}
{{- end }}
{{- end }}

{{/*
Create the Redis image repository
*/}}
{{- define "nextcloud.redisImageRepository" -}}
{{- if .Values.global.imageRegistry }}
{{- printf "%s/%s" .Values.global.imageRegistry .Values.redis.image }}
{{- else }}
{{- .Values.redis.image }}
{{- end }}
{{- end }}

{{/*
Create the image tag
*/}}
{{- define "nextcloud.imageTag" -}}
{{- .Values.nextcloud.image.tag }}
{{- end }}

{{/*
Create the image pull policy
*/}}
{{- define "nextcloud.imagePullPolicy" -}}
{{- .Values.nextcloud.image.pullPolicy }}
{{- end }}

{{/*
Create the image pull secrets
*/}}
{{- define "nextcloud.imagePullSecrets" -}}
{{- if .Values.global.imagePullSecrets }}
imagePullSecrets:
{{- range .Values.global.imagePullSecrets }}
  - name: {{ . }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create the security context
*/}}
{{- define "nextcloud.securityContext" -}}
{{- if .Values.nextcloud.securityContext }}
securityContext:
{{- toYaml .Values.nextcloud.securityContext | nindent 2 }}
{{- end }}
{{- end }}

{{/*
Create the pod security context
*/}}
{{- define "nextcloud.podSecurityContext" -}}
{{- if .Values.nextcloud.podSecurityContext }}
securityContext:
{{- toYaml .Values.nextcloud.podSecurityContext | nindent 2 }}
{{- end }}
{{- end }}

{{/*
Create the resources
*/}}
{{- define "nextcloud.resources" -}}
{{- if .Values.nextcloud.resources }}
resources:
{{- toYaml .Values.nextcloud.resources | nindent 2 }}
{{- end }}
{{- end }}

{{/*
Create the liveness probe
*/}}
{{- define "nextcloud.livenessProbe" -}}
{{- if .Values.nextcloud.livenessProbe }}
livenessProbe:
{{- toYaml .Values.nextcloud.livenessProbe | nindent 2 }}
{{- end }}
{{- end }}

{{/*
Create the readiness probe
*/}}
{{- define "nextcloud.readinessProbe" -}}
{{- if .Values.nextcloud.readinessProbe }}
readinessProbe:
{{- toYaml .Values.nextcloud.readinessProbe | nindent 2 }}
{{- end }}
{{- end }}

{{/*
Create the environment variables
*/}}
{{- define "nextcloud.env" -}}
env:
{{- range $key, $value := .Values.nextcloud.config }}
- name: {{ $key }}
  value: {{ $value | quote }}
{{- end }}
{{- end }}

{{/*
Create the volume mounts
*/}}
{{- define "nextcloud.volumeMounts" -}}
volumeMounts:
- name: data
  mountPath: /var/www/html/data
- name: config
  mountPath: /var/www/html/config
- name: apps
  mountPath: /var/www/html/custom_apps
{{- end }}

{{/*
Create the volumes
*/}}
{{- define "nextcloud.volumes" -}}
volumes:
- name: data
  persistentVolumeClaim:
    claimName: {{ include "nextcloud.dataPVCName" . }}
- name: config
  persistentVolumeClaim:
    claimName: {{ include "nextcloud.configPVCName" . }}
- name: apps
  persistentVolumeClaim:
    claimName: {{ include "nextcloud.appsPVCName" . }}
{{- end }}

{{/*
Create the node selector
*/}}
{{- define "nextcloud.nodeSelector" -}}
{{- if .Values.nodeSelector }}
nodeSelector:
{{- toYaml .Values.nodeSelector | nindent 2 }}
{{- end }}
{{- end }}

{{/*
Create the tolerations
*/}}
{{- define "nextcloud.tolerations" -}}
{{- if .Values.tolerations }}
tolerations:
{{- toYaml .Values.tolerations | nindent 2 }}
{{- end }}
{{- end }}

{{/*
Create the affinity
*/}}
{{- define "nextcloud.affinity" -}}
{{- if .Values.affinity }}
affinity:
{{- toYaml .Values.affinity | nindent 2 }}
{{- end }}
{{- end }}
