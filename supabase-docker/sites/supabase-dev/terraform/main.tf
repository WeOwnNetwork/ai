# supabase-dev - Main Infrastructure
# Managed by OpenTofu
#
# Provisions a single DigitalOcean droplet running the Supabase self-hosted
# stack (Postgres + PostgREST + GoTrue + Realtime + Studio) behind Caddy.
# All application secrets are fetched from Infisical at container runtime —
# none are written to disk or stored in terraform state.

resource "digitalocean_droplet" "supabase" {
  name       = "supabase-dev"
  image      = var.droplet_image
  size       = var.droplet_size
  region     = var.region
  monitoring = true
  # If skinny backups are on, disable the DO automated backup add-on to avoid
  # double-billing for protection that pg_dump + volume tars already cover.
  backups = var.enable_skinny_backups ? false : true

  ssh_keys = [var.ssh_key_fingerprint]

  user_data = templatefile("${path.module}/templates/cloud-init.yaml", {
    project_name            = "supabase_dev"
    domain                  = var.domain
    postgres_image          = var.postgres_image
    postgrest_image         = var.postgrest_image
    gotrue_image            = var.gotrue_image
    realtime_image          = var.realtime_image
    studio_image            = var.studio_image
    caddy_image             = var.caddy_image
    postgres_version        = var.postgres_version
    db_name                 = var.db_name
    db_user                 = var.db_user
    enable_pgvector         = var.enable_pgvector
    enable_studio           = var.enable_studio
    enable_realtime         = var.enable_realtime
    infisical_client_id     = var.infisical_client_id
    infisical_client_secret = var.infisical_client_secret
    infisical_project_id    = var.infisical_project_id
    infisical_environment   = var.infisical_environment
    enable_skinny_backups   = var.enable_skinny_backups
    backup_remote_storage   = var.backup_remote_storage
    backup_do_spaces_bucket = var.backup_do_spaces_bucket
    backup_do_spaces_region = var.backup_do_spaces_region
  })

  tags = ["supabase-dev", "supabase", "pop-db", "weown-ai"]

  lifecycle {
    ignore_changes = [user_data]
  }
}

resource "digitalocean_reserved_ip" "supabase" {
  region = var.region
}

resource "digitalocean_reserved_ip_assignment" "supabase" {
  ip_address = digitalocean_reserved_ip.supabase.ip_address
  droplet_id = digitalocean_droplet.supabase.id
}

resource "digitalocean_firewall" "supabase" {
  name        = "supabase-dev-fw"
  droplet_ids = [digitalocean_droplet.supabase.id]

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

  # PostgreSQL (only from within the VPC — cross-droplet app access).
  # External clients should go through PostgREST on 443, not raw 5432.
  inbound_rule {
    protocol         = "tcp"
    port_range       = "5432"
    source_addresses = ["10.0.0.0/8"]
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

  tags = ["supabase-dev"]
}
