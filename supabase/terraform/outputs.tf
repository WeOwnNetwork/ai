output "namespace" {
  description = "kubernetes namespace where supabase runs"
  value       = kubernetes_namespace.supabase.metadata[0].name
}

output "helm_release_name" {
  description = "helm release name"
  value       = helm_release.supabase.name
}

output "helm_release_status" {
  description = "helm release status"
  value       = helm_release.supabase.status
}

output "postgres_service_dns" {
  description = "internal cluster DNS for postgres — use from apps in this namespace"
  value       = "${helm_release.supabase.name}-postgres.${kubernetes_namespace.supabase.metadata[0].name}.svc.cluster.local"
}

output "caddy_service_dns" {
  description = "internal cluster DNS for the caddy edge (nginx-ingress routes here)"
  value       = "${helm_release.supabase.name}-caddy.${kubernetes_namespace.supabase.metadata[0].name}.svc.cluster.local"
}
