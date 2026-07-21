# claw-weown-tools - Main Infrastructure
# Managed by OpenTofu

resource "digitalocean_droplet" "openclaw" {
  name       = "claw-weown-tools"
  image      = var.droplet_image
  size       = var.droplet_size
  region     = var.region
  monitoring = true
  backups    = var.enable_skinny_backups ? false : true

  ssh_keys = var.ssh_key_fingerprints

  user_data = templatefile("${path.module}/templates/cloud-init.yaml", {
    project_name            = "claw_weown_tools"
    domain                  = var.domain
    openclaw_image          = var.openclaw_image
    caddy_image             = var.caddy_image
    openclaw_internal_port  = var.openclaw_internal_port
    infisical_client_id     = var.infisical_client_id
    infisical_client_secret = var.infisical_client_secret
    infisical_project_id    = var.infisical_project_id
    infisical_environment   = var.infisical_environment
    enable_skinny_backups   = var.enable_skinny_backups
    backup_remote_storage   = var.backup_remote_storage
    backup_do_spaces_bucket = var.backup_do_spaces_bucket
    backup_do_spaces_region = var.backup_do_spaces_region
  })

  # Base tags. Feature tags + commit tag are added at runtime by:
  #   - scripts/tag-droplet.sh (helper, invoked by ansible deploy + bootstrap scripts)
  #   - ansible/deploy.yml (adds skinny-backup + commit-<sha>)
  #   - scripts/bootstrap-otel-agent.sh (adds otel)
  # See docs/INFRA_BOOTSTRAP_PATTERN.md "DO tag taxonomy" for the full scheme.
  # `ignore_changes = [tags]` prevents tofu apply from reverting runtime-added
  # tags on subsequent runs.
  tags = ["claw-weown-tools", "openclaw", "ai", "weown-ai"]

  lifecycle {
    # ssh_keys is create-time only (DO injects at provision); ignore it so adding
    # an operator key to var.extra_ssh_key_fingerprints provisions NEW droplets with
    # it WITHOUT replacing existing ones. Ongoing access is via OPS_AUTHORIZED_KEYS.
    ignore_changes = [user_data, tags, ssh_keys]
  }
}

resource "digitalocean_reserved_ip" "openclaw" {
  region = var.region
}

resource "digitalocean_reserved_ip_assignment" "openclaw" {
  ip_address = digitalocean_reserved_ip.openclaw.ip_address
  droplet_id = digitalocean_droplet.openclaw.id
}

#trivy:ignore:AVD-DIG-0001  # Public web server: HTTP/HTTPS inbound from internet is required by design
#trivy:ignore:AVD-DIG-0003  # Public web server: unrestricted outbound required for OS updates, ACME, APIs
resource "digitalocean_firewall" "openclaw" {
  name        = "claw-weown-tools-fw"
  droplet_ids = [digitalocean_droplet.openclaw.id]

  # SSH — restrict via var.ssh_source_cidrs (default is wide-open; production should pin)
  inbound_rule {
    protocol         = "tcp"
    port_range       = "22"
    source_addresses = var.ssh_source_cidrs
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

  tags = ["claw-weown-tools"]
}
