# =============================================================================
# Infisical Secrets Operator — cluster-wide install.
# Provides the InfisicalSecret CRD that the supabase chart's
# templates/infisical-secret.yaml depends on.
# =============================================================================

resource "helm_release" "infisical_operator" {
  name             = "infisical-secrets-operator"
  namespace        = var.infisical_operator_namespace
  create_namespace = true

  repository = "https://dl.cloudsmith.io/public/infisical/helm-charts/helm/charts/"
  chart      = "secrets-operator"
  version    = var.infisical_operator_chart_version != "" ? var.infisical_operator_chart_version : null

  # Bypass helm_release provider's post-install openapi validation.
  # The operator ships 7 CRDs; validation fetches openapi.json from the cluster
  # which can time out on CRD-heavy installs (see hashicorp/terraform-provider-helm#1533).
  # Install itself is unaffected — only the validation step is skipped.
  disable_openapi_validation = true
  timeout                    = 600
}

# =============================================================================
# Supabase namespace + bootstrap secret.
# =============================================================================

resource "kubernetes_namespace" "supabase" {
  metadata {
    name = var.namespace
    labels = {
      "app.kubernetes.io/part-of" = "weown-mvp"
    }
  }
}

# Bootstrap credential the Infisical Secrets Operator uses to authenticate to
# Infisical Cloud. The operator then syncs the 12 runtime supabase secrets
# from Infisical into the supabase-secrets Secret in this namespace.
resource "kubernetes_secret" "infisical_universal_auth" {
  metadata {
    name      = "infisical-universal-auth"
    namespace = kubernetes_namespace.supabase.metadata[0].name
  }

  data = {
    clientId     = var.infisical_client_id
    clientSecret = var.infisical_client_secret
  }

  type = "Opaque"
}

# =============================================================================
# Supabase helm release.
# Consumes ../helm chart with values-weown-tools.yaml overrides.
# Depends on CRD availability (via infisical_operator) + bootstrap secret.
# =============================================================================

resource "helm_release" "supabase" {
  name      = var.release_name
  namespace = kubernetes_namespace.supabase.metadata[0].name

  chart  = var.chart_path
  values = [file(var.values_file)]

  # Override Infisical project/env slugs so we can retarget without editing
  # values-weown-tools.yaml.
  set {
    name  = "infisical.projectSlug"
    value = var.infisical_project_id
  }

  set {
    name  = "infisical.envSlug"
    value = var.infisical_environment
  }

  # Wait for Job hooks (extensions) + all resources ready before returning.
  wait          = true
  wait_for_jobs = true
  timeout       = 600

  depends_on = [
    helm_release.infisical_operator,
    kubernetes_secret.infisical_universal_auth,
  ]
}
