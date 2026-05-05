# ${var.project_name}: - Main Infrastructure
# Managed by OpenTofu

resource "digitalocean_droplet" "web" {
  name       = var.project_name
  image      = var.droplet_image
  size       = var.droplet_size
  region     = var.region
  monitoring = true
  backups    = false # Using skinny volume backups instead
  ssh_keys   = [var.ssh_key_fingerprint]

  user_data = templatefile("${path.module}/templates/cloud-init.yaml", {
    project_name            = var.project_name
    domain                  = var.domain
    domain_style            = var.domain_style
    minimus_token           = var.minimus_token
    wp_image                = var.wp_image
    caddy_image             = var.caddy_image
    mariadb_version         = var.mariadb_version
    mysql_database          = var.mysql_database
    mysql_user              = var.mysql_user
    mysql_password          = var.mysql_password
    mysql_root_password     = var.mysql_root_password
    enable_wordfence_waf    = var.enable_wordfence_waf
    enable_infisical        = var.enable_infisical
    infisical_token         = var.infisical_token
    infisical_project_id    = var.infisical_project_id
    infisical_environment   = var.infisical_environment
    infisical_client_id     = var.infisical_client_id
    infisical_client_secret = var.infisical_client_secret
  })

  tags = [var.project_name, "wordpress", "opentofu-template"]

  lifecycle {
    ignore_changes = [user_data]
  }
}

resource "digitalocean_reserved_ip_assignment" "web" {
  ip_address = var.reserved_ip
  droplet_id = digitalocean_droplet.web.id
}

resource "digitalocean_firewall" "web" {
  name        = "${var.project_name}-fw"
  droplet_ids = [digitalocean_droplet.web.id]

  # SSH — restrict via var.allowed_ssh_sources (set to your ops IPs in terraform.tfvars)
  inbound_rule {
    protocol         = "tcp"
    port_range       = "22"
    source_addresses = var.allowed_ssh_sources
  }

  # HTTP — public ingress required for ACME challenges and HTTP→HTTPS redirects
  #trivy:ignore:AVD-DIG-0001
  inbound_rule {
    protocol         = "tcp"
    port_range       = "80"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  # HTTPS — public ingress required for web traffic
  #trivy:ignore:AVD-DIG-0001
  inbound_rule {
    protocol         = "tcp"
    port_range       = "443"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  # HTTPS/QUIC (HTTP/3) — public ingress required for web traffic
  #trivy:ignore:AVD-DIG-0001
  inbound_rule {
    protocol         = "udp"
    port_range       = "443"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  # All outbound TCP — required for package updates, DNS, HTTPS egress, etc.
  #trivy:ignore:AVD-DIG-0002
  outbound_rule {
    protocol              = "tcp"
    port_range            = "1-65535"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  # All outbound UDP — required for DNS and NTP
  #trivy:ignore:AVD-DIG-0002
  outbound_rule {
    protocol              = "udp"
    port_range            = "1-65535"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  # ICMP for ping/diagnostics
  #trivy:ignore:AVD-DIG-0002
  outbound_rule {
    protocol              = "icmp"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }
}

resource "terraform_data" "rotate_secrets" {
  triggers_replace = {
    rotation = var.secret_rotation_version
  }

  provisioner "remote-exec" {
    inline = [
      "bash /opt/${var.project_name}/rotate-secrets.sh"
    ]

    connection {
      type        = "ssh"
      host        = var.reserved_ip
      user        = "root"
      private_key = file(var.private_key_path)
    }
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
