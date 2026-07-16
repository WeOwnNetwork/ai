locals {
  # Respect var.kubeconfig_path if set (via TF_VAR_kubeconfig_path env var for
  # multi-cluster workflows or CI). Fall back to ~/.kube/config default.
  kubeconfig_path = var.kubeconfig_path != "" ? var.kubeconfig_path : pathexpand("~/.kube/config")
}

provider "kubernetes" {
  config_path    = local.kubeconfig_path
  config_context = var.kubernetes_context
}

provider "helm" {
  kubernetes {
    config_path    = local.kubeconfig_path
    config_context = var.kubernetes_context
  }
}
