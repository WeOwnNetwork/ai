# burnedout-xyz - Outputs

output "droplet_ip" {
  description = "Public IPv4 address of the droplet"
  value       = digitalocean_droplet.web.ipv4_address
}

output "reserved_ip" {
  description = "Reserved (static) IP address — use this for DNS"
  value       = digitalocean_reserved_ip.web.ip_address
}

output "droplet_id" {
  description = "Droplet ID"
  value       = digitalocean_droplet.web.id
}

output "ssh_command" {
  description = "SSH command to connect to the droplet"
  value       = "ssh root@${digitalocean_reserved_ip.web.ip_address}"
}

output "site_url" {
  description = "Production site URL"
  value       = "https://burnedout.xyz"
}

output "app_directory" {
  description = "Application directory on the droplet"
  value       = "/opt/burnedout"
}
