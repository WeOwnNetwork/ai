# -----------------------------------------------------------------------------
# Cluster + release targeting
# -----------------------------------------------------------------------------

variable "kubernetes_context" {
  description = "kubectl context to target (e.g. do-atl1-weown-app-k8s-cluster-atl1 for labs)"
  type        = string
  default     = "do-atl1-weown-app-k8s-cluster-atl1"
}

variable "kubeconfig_path" {
  description = "Path to kubeconfig file. Empty = ~/.kube/config. Override via TF_VAR_kubeconfig_path env var for multi-cluster workflows or CI."
  type        = string
  default     = ""
}

variable "namespace" {
  description = "kubernetes namespace for supabase workloads"
  type        = string
  default     = "supabase"
}

variable "release_name" {
  description = "helm release name for the supabase chart"
  type        = string
  default     = "supabase"
}

variable "chart_path" {
  description = "path to the supabase helm chart, relative to this terraform module"
  type        = string
  default     = "../helm"
}

variable "values_file" {
  description = "path to the helm values override file, relative to this terraform module"
  type        = string
  default     = "../helm/values-weown-tools.yaml"
}

# -----------------------------------------------------------------------------
# Infisical Secrets Operator install (cluster-wide capability)
# -----------------------------------------------------------------------------

variable "infisical_operator_namespace" {
  description = "namespace for the Infisical Secrets Operator install"
  type        = string
  default     = "infisical-operator-system"
}

variable "infisical_operator_chart_version" {
  description = "helm chart version for infisical/secrets-operator (empty = latest)"
  type        = string
  default     = ""
}

# -----------------------------------------------------------------------------
# Infisical bootstrap credentials
# Fetched via `infisical run --projectId <bootstrap-project> --env <env> -- tofu apply`
# which injects these as TF_VAR_* env vars from the bootstrap Infisical project.
# -----------------------------------------------------------------------------

variable "infisical_client_id" {
  description = "Infisical universal-auth Client ID for the runtime machine identity (Viewer role scoped to the runtime project's env)"
  type        = string
  sensitive   = true
}

variable "infisical_client_secret" {
  description = "Infisical universal-auth Client Secret for the runtime machine identity"
  type        = string
  sensitive   = true
}

variable "infisical_project_id" {
  description = "Slug of the runtime Infisical project (where the 12 supabase runtime secrets live)"
  type        = string
}

variable "infisical_environment" {
  description = "Env slug within the runtime Infisical project"
  type        = string
  default     = "prod"
}
