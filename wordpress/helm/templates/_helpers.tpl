{{/*
Expand the name of the chart.
*/}}
{{- define "wordpress.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "wordpress.fullname" -}}
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
{{- define "wordpress.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "wordpress.labels" -}}
helm.sh/chart: {{ include "wordpress.chart" . }}
{{ include "wordpress.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: wordpress-platform
{{- end }}

{{/*
Selector labels
*/}}
{{- define "wordpress.selectorLabels" -}}
app.kubernetes.io/name: {{ include "wordpress.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "wordpress.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "wordpress.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Create the name of the secret to use
*/}}
{{- define "wordpress.secretName" -}}
{{- if .Values.existingSecret }}
{{- printf "%s" .Values.existingSecret }}
{{- else }}
{{- printf "%s" (include "wordpress.fullname" .) }}
{{- end }}
{{- end }}

{{/*
Get the password secret.
*/}}
{{- define "wordpress.secretPasswordKey" -}}
{{- if .Values.existingSecret }}
{{- .Values.existingSecretPasswordKey }}
{{- else }}
{{- printf "wordpress-password" }}
{{- end }}
{{- end }}

{{/*
Return the proper Database hostname
*/}}
{{- define "wordpress.databaseHost" -}}
{{- if .Values.mariadb.enabled }}
{{- printf "%s-%s" .Release.Name "mariadb" }}
{{- else }}
{{- printf "%s" .Values.externalDatabase.host }}
{{- end }}
{{- end }}

{{/*
Return the proper Database port
*/}}
{{- define "wordpress.databasePort" -}}
{{- if .Values.mariadb.enabled }}
{{- printf "3306" }}
{{- else }}
{{- printf "%d" (.Values.externalDatabase.port | int ) }}
{{- end }}
{{- end }}

{{/*
Return the proper Database name
*/}}
{{- define "wordpress.databaseName" -}}
{{- if .Values.mariadb.enabled }}
{{- printf "%s" .Values.mariadb.auth.database }}
{{- else }}
{{- printf "%s" .Values.externalDatabase.database }}
{{- end }}
{{- end }}

{{/*
Return the proper Database user
*/}}
{{- define "wordpress.databaseUser" -}}
{{- if .Values.mariadb.enabled }}
{{- printf "%s" .Values.mariadb.auth.username }}
{{- else }}
{{- printf "%s" .Values.externalDatabase.user }}
{{- end }}
{{- end }}

{{/*
Return the proper Redis hostname
*/}}
{{- define "wordpress.redisHost" -}}
{{- if .Values.redis.enabled }}
{{- printf "%s-%s-master" .Release.Name "redis" }}
{{- else }}
{{- printf "%s" .Values.externalRedis.host }}
{{- end }}
{{- end }}

{{/*
Return the proper Redis port
*/}}
{{- define "wordpress.redisPort" -}}
{{- if .Values.redis.enabled }}
{{- printf "6379" }}
{{- else }}
{{- printf "%d" (.Values.externalRedis.port | int ) }}
{{- end }}
{{- end }}

{{/*
Return the WordPress configuration secret name
*/}}
{{- define "wordpress.configSecretName" -}}
{{- printf "%s-config" (include "wordpress.fullname" .) }}
{{- end }}

{{/*
Return the MariaDB secret name
*/}}
{{- define "wordpress.mariadb.secretName" -}}
{{- if .Values.mariadb.existingSecret }}
{{- printf "%s" .Values.mariadb.existingSecret }}
{{- else }}
{{- printf "%s-mariadb" .Release.Name }}
{{- end }}
{{- end }}

{{/*
Return MariaDB port
*/}}
{{- define "wordpress.mariadb.port" -}}
{{- printf "3306" }}
{{- end }}

{{/*
Validate WordPress configuration
*/}}
{{- define "wordpress.validateValues" -}}
{{- if and (not .Values.mysql.enabled) (not .Values.externalDatabase.host) }}
wordpress: database
   You must enable MariaDB (--set mysql.enabled=true) or
   set an external database host (--set externalDatabase.host=DATABASE_HOST)
{{- end }}
{{- end }}

{{/*
Create PVC name for WordPress content
*/}}
{{- define "wordpress.content.claimName" -}}
{{- printf "%s-content" (include "wordpress.fullname" .) }}
{{- end }}

{{/*
Create PVC name for WordPress config
*/}}
{{- define "wordpress.config.claimName" -}}
{{- printf "%s-config" (include "wordpress.fullname" .) }}
{{- end }}

{{/*
Create PVC name for WordPress cache
*/}}
{{- define "wordpress.cache.claimName" -}}
{{- printf "%s-cache" (include "wordpress.fullname" .) }}
{{- end }}

{{/*
Generate certificates secret name
*/}}
{{- define "wordpress.tlsSecret" -}}
{{- printf "%s-tls" (include "wordpress.fullname" .) }}
{{- end }}

{{/*
Generate backup job name
*/}}
{{- define "wordpress.backup.jobName" -}}
{{- printf "%s-backup" (include "wordpress.fullname" .) }}
{{- end }}

{{/*
Generate monitoring service name
*/}}
{{- define "wordpress.monitoring.serviceName" -}}
{{- printf "%s-monitoring" (include "wordpress.fullname" .) }}
{{- end }}

{{/*
Return the appropriate apiVersion for PodDisruptionBudget
*/}}
{{- define "wordpress.pdb.apiVersion" -}}
{{- if $.Capabilities.APIVersions.Has "policy/v1/PodDisruptionBudget" }}
{{- print "policy/v1" }}
{{- else }}
{{- print "policy/v1beta1" }}
{{- end }}
{{- end }}

{{/*
Return the appropriate apiVersion for HorizontalPodAutoscaler
*/}}
{{- define "wordpress.hpa.apiVersion" -}}
{{- if $.Capabilities.APIVersions.Has "autoscaling/v2/HorizontalPodAutoscaler" }}
{{- print "autoscaling/v2" }}
{{- else if $.Capabilities.APIVersions.Has "autoscaling/v2beta2/HorizontalPodAutoscaler" }}
{{- print "autoscaling/v2beta2" }}
{{- else }}
{{- print "autoscaling/v2beta1" }}
{{- end }}
{{- end }}

{{/*
Return the appropriate apiVersion for NetworkPolicy
*/}}
{{- define "wordpress.networkPolicy.apiVersion" -}}
{{- if $.Capabilities.APIVersions.Has "networking.k8s.io/v1/NetworkPolicy" }}
{{- print "networking.k8s.io/v1" }}
{{- else }}
{{- print "networking.k8s.io/v1beta1" }}
{{- end }}
{{- end }}

{{/*
Compile all warnings into a single message, and call fail.
*/}}
{{- define "wordpress.validateValues.mysql" -}}
{{- if and (not .Values.mariadb.enabled) (not .Values.externalDatabase.host) }}
INVALID CONFIGURATION: You must enable MariaDB or set an external database
{{- end }}
{{- end }}

{{/*
WordPress security configuration validation
*/}}
{{- define "wordpress.validateValues.security" -}}
{{- if .Values.wordpress.security.runAsUser }}
{{- if lt (.Values.wordpress.security.runAsUser | int) 1000 }}
SECURITY WARNING: runAsUser should be >= 1000 for enhanced security
{{- end }}
{{- end }}
{{- if not .Values.wordpress.security.runAsNonRoot }}
SECURITY WARNING: runAsNonRoot should be true for enhanced security
{{- end }}
{{- end }}
