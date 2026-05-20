# claw-weown-tools - Main Infrastructure
# Managed by OpenTofu

data "infisical_secrets" "shared" {
  env_slug     = "prod"
  workspace_id = "6c05dbb2-dc9f-41a8-8b4d-d50d515115e8"
  folder_path  = "/Shared"
}

data "infisical_secrets" "instance" {
  env_slug     = "prod"
  workspace_id = "6c05dbb2-dc9f-41a8-8b4d-d50d515115e8"
  folder_path  = "/claw-weown-tools"
}

resource "digitalocean_droplet" "web" {
  name       = "claw-weown-tools"
  image      = var.droplet_image
  size       = var.droplet_size
  region     = var.region
  monitoring = true
  backups    = false
  ssh_keys   = [var.ssh_key_fingerprint]

  user_data = templatefile("${path.module}/templates/cloud-init.yaml", {
    domain                 = data.infisical_secrets.instance.secrets["DOMAIN"].value
    minimus_token          = data.infisical_secrets.shared.secrets["MINIMUS_TOKEN"].value
    openclaw_image         = data.infisical_secrets.shared.secrets["OPENCLAW_IMAGE"].value
    caddy_image            = data.infisical_secrets.shared.secrets["CADDY_IMAGE"].value
    openclaw_gateway_token = data.infisical_secrets.instance.secrets["OPENCLAW_GATEWAY_TOKEN"].value
    openrouter_api_key     = data.infisical_secrets.shared.secrets["OPENROUTER_API_KEY"].value
    signoz_ingestion_key   = data.infisical_secrets.shared.secrets["SIGNOZ_INGESTION_KEY"].value
  })

  tags = ["claw-weown-tools", "openclaw", "weown-ai"]

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

#trivy:ignore:AVD-DIG-0001
#trivy:ignore:AVD-DIG-0003
resource "digitalocean_firewall" "web" {
  name        = "claw-weown-tools-fw"
  droplet_ids = [digitalocean_droplet.web.id]

  inbound_rule {
    protocol         = "tcp"
    port_range       = "22"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  inbound_rule {
    protocol         = "tcp"
    port_range       = "80"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  inbound_rule {
    protocol         = "tcp"
    port_range       = "443"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  inbound_rule {
    protocol         = "udp"
    port_range       = "443"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  outbound_rule {
    protocol              = "tcp"
    port_range            = "1-65535"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  outbound_rule {
    protocol              = "udp"
    port_range            = "1-65535"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  outbound_rule {
    protocol              = "icmp"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }
}
