# stage-burnedout-xyz - Outputs

output "droplet_ip" {
  description = "Public IPv4 address of the droplet"
  value       = digitalocean_droplet.web.ipv4_address
}

output "reserved_ip" {
  value = var.reserved_ip
}

output "droplet_id" {
  description = "Droplet ID"
  value       = digitalocean_droplet.web.id
}

output "ssh_command" {
  value = "ssh root@${var.reserved_ip}"
}

output "site_url" {
  description = "Production site URL"
  value       = "https://stage.burnedout.xyz"
}

output "app_directory" {
  description = "Application directory on the droplet"
  value       = "/opt/stageburnedoutxyz"
}
