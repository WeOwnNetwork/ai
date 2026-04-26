# test-keycloak - Terraform Outputs
# Managed by OpenTofu

output "droplet_ip" {
  description = "Droplet IPv4 address"
  value       = digitalocean_reserved_ip.keycloak.ip_address
}

output "droplet_id" {
  description = "Droplet ID"
  value       = digitalocean_droplet.keycloak.id
}

output "domain" {
  description = "Primary domain"
  value       = var.domain
}

output "keycloak_url" {
  description = "Keycloak admin console URL"
  value       = "https://${var.domain}/admin"
}

output "keycloak_api_url" {
  description = "Keycloak API URL"
  value       = "https://${var.domain}/realms/master"
}
