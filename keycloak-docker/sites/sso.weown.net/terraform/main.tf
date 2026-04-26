# sso - Main Infrastructure
# Managed by OpenTofu

resource "digitalocean_droplet" "keycloak" {
  name       = "sso"
  image      = var.droplet_image
  size       = var.droplet_size
  region     = var.region
  monitoring = true
  backups    = false

  ssh_keys = [var.ssh_key_fingerprint]

  user_data = templatefile("${path.module}/templates/cloud-init.yaml", {
    project_name            = "sso"
    domain                  = var.domain
    keycloak_image          = var.keycloak_image
    caddy_image             = var.caddy_image
    postgres_version        = var.postgres_version
    db_name                 = var.db_name
    db_user                 = var.db_user
    db_password             = var.db_password
    db_root_password        = var.db_root_password
    keycloak_admin_username = var.keycloak_admin_username
    keycloak_admin_password = var.keycloak_admin_password
    enable_infisical        = var.enable_infisical
    infisical_token         = var.enable_infisical ? var.infisical_token : ""
    infisical_project_id     = var.enable_infisical ? var.infisical_project_id : ""
    infisical_environment   = var.enable_infisical ? var.infisical_environment : ""
  })

  tags = ["sso", "keycloak", "sso", "weown-ai"]

  lifecycle {
    ignore_changes = [user_data]
  }
}

resource "digitalocean_reserved_ip" "keycloak" {
  region = var.region
}

resource "digitalocean_reserved_ip_assignment" "keycloak" {
  ip_address = digitalocean_reserved_ip.keycloak.ip_address
  droplet_id = digitalocean_droplet.keycloak.id
}

resource "digitalocean_firewall" "keycloak" {
  name        = "sso-fw"
  droplet_ids = [digitalocean_droplet.keycloak.id]

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

  # PostgreSQL (only from within the VPC)
  inbound_rule {
    protocol         = "tcp"
    port_range       = "5432"
    source_addresses = ["10.0.0.0/8"]
  }

  # All outbound
  outbound_rule {
    protocol              = "tcp"
    port_range           = "1-65535"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  outbound_rule {
    protocol              = "udp"
    port_range            = "1-65535"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  tags = ["sso"]
}
