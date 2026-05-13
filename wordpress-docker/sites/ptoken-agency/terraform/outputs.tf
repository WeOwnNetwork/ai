# ptoken-agency - Outputs

output "droplet_ip" {
  description = "Public IPv4 address"
  value       = digitalocean_droplet.web.ipv4_address
}

output "reserved_ip" {
  description = "Reserved IP for DNS"
  value       = digitalocean_reserved_ip.web.ip_address
}

output "droplet_id" {
  description = "Droplet ID"
  value       = digitalocean_droplet.web.id
}

output "ssh_command" {
  description = "SSH command"
  value       = "ssh root@${digitalocean_reserved_ip.web.ip_address}"
}

output "site_url" {
  description = "Production site URL"
  value       = "https://www.ptoken.agency"
}

output "app_directory" {
  description = "App directory on droplet"
  value       = "/opt/ptoken"
}
