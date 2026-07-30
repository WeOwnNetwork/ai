# supabase-dev - Terraform Outputs
# Managed by OpenTofu

output "droplet_ip" {
  description = "Droplet IPv4 address (reserved IP)"
  value       = digitalocean_reserved_ip.supabase.ip_address
}

output "reserved_ip" {
  description = "Reserved IP address (alias for droplet_ip, backward compatibility)"
  value       = digitalocean_reserved_ip.supabase.ip_address
}

output "droplet_id" {
  description = "Droplet ID"
  value       = digitalocean_droplet.supabase.id
}

output "domain" {
  description = "Primary domain"
  value       = var.domain
}

output "studio_url" {
  description = "Supabase Studio admin UI URL"
  value       = var.enable_studio ? "https://${var.domain}" : null
}

output "rest_api_url" {
  description = "PostgREST API endpoint (REST over Postgres)"
  value       = "https://${var.domain}/rest/v1"
}

output "auth_url" {
  description = "GoTrue auth endpoint (issues JWTs for RLS)"
  value       = "https://${var.domain}/auth/v1"
}

output "realtime_url" {
  description = "Realtime WebSocket endpoint (Postgres change subscriptions)"
  value       = var.enable_realtime ? "wss://${var.domain}/realtime/v1" : null
}

output "postgres_host_internal" {
  description = "Postgres host reachable from inside the droplet VPC (port 5432)"
  value       = digitalocean_droplet.supabase.ipv4_address_private
  sensitive   = true
}
