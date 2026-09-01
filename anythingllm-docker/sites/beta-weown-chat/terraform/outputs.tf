# beta-weown-chat - Terraform Outputs
# Managed by OpenTofu

output "droplet_ip" {
  description = "Droplet IPv4 address (reserved IP)"
  value       = digitalocean_reserved_ip.anythingllm.ip_address
}

output "reserved_ip" {
  description = "Reserved IP address (alias for droplet_ip, backward compatibility)"
  value       = digitalocean_reserved_ip.anythingllm.ip_address
}

output "droplet_private_ip" {
  description = "VPC-private IPv4 — the address peers reach this droplet on inside the VPC (e.g. the OpenBao platform store's firewall allowlist). Public IPs are not usable for that."
  value       = digitalocean_droplet.anythingllm.ipv4_address_private
}

output "droplet_id" {
  description = "Droplet ID"
  value       = digitalocean_droplet.anythingllm.id
}

output "domain" {
  description = "Primary domain"
  value       = var.domain
}

output "anythingllm_url" {
  description = "AnythingLLM application URL"
  value       = "https://${var.domain}"
}

output "infisical_project" {
  description = "Infisical project ID for secrets management"
  value       = var.infisical_project_id
}
