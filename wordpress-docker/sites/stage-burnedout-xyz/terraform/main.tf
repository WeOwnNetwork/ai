# stage-burnedout-xyz - Main Infrastructure
# Managed by OpenTofu

resource "digitalocean_droplet" "web" {
  name       = "stage-burnedout-xyz"
  image      = var.droplet_image
  size       = var.droplet_size
  region     = var.region
  monitoring = true
  backups    = false # Using skinny volume backups instead
  ssh_keys   = [var.ssh_key_fingerprint]

  user_data = templatefile("${path.module}/templates/cloud-init.yaml", {
    project_name          = "stageburnedoutxyz"
    domain                = var.domain
    domain_style          = var.domain_style
    minimus_token         = var.minimus_token
    wp_image              = var.wp_image
    caddy_image           = var.caddy_image
    mariadb_version       = var.mariadb_version
    mysql_database        = var.mysql_database
    mysql_user            = var.mysql_user
    mysql_password        = var.mysql_password
    mysql_root_password   = var.mysql_root_password
    enable_wordfence_waf  = var.enable_wordfence_waf
    enable_infisical      = var.enable_infisical
    infisical_token       = var.infisical_token
    infisical_project_id  = var.infisical_project_id
    infisical_environment = var.infisical_environment
  })

  tags = ["stage-burnedout-xyz", "wordpress", "weown-ai"]

  lifecycle {
    ignore_changes = [user_data]
  }
}

resource "digitalocean_reserved_ip" "web" {
  region = var.region
}

resource "digitalocean_reserved_ip_assignment" "web" {
  ip_address = digitalocean_reserved_ip.web.ip_address
  droplet_id = digitalocean_droplet.web.id
}

resource "digitalocean_firewall" "web" {
  name        = "stage-burnedout-xyz-fw"
  droplet_ids = [digitalocean_droplet.web.id]

  # SSH
  inbound_rule {
    protocol         = "tcp"
    port_range       = "22"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  # HTTP (for ACME challenges and redirects)
  inbound_rule {
    protocol         = "tcp"
    port_range       = "80"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  # HTTPS
  inbound_rule {
    protocol         = "tcp"
    port_range       = "443"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  # HTTPS/QUIC (HTTP/3)
  inbound_rule {
    protocol         = "udp"
    port_range       = "443"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  # All outbound TCP
  outbound_rule {
    protocol              = "tcp"
    port_range            = "1-65535"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  # All outbound UDP
  outbound_rule {
    protocol              = "udp"
    port_range            = "1-65535"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  # ICMP for ping/diagnostics
  outbound_rule {
    protocol              = "icmp"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }
}

# Uncomment to manage DNS via OpenTofu (if domain is on DigitalOcean)
#
# resource "digitalocean_domain" "site" {
#   name = var.domain
# }
#
# resource "digitalocean_record" "root" {
#   domain = digitalocean_domain.site.id
#   type   = "A"
#   name   = "@"
#   value  = digitalocean_reserved_ip.web.ip_address
#   ttl    = 300
# }
#
# resource "digitalocean_record" "www" {
#   domain = digitalocean_domain.site.id
#   type   = "A"
#   name   = "www"
#   value  = digitalocean_reserved_ip.web.ip_address
#   ttl    = 300
# }
