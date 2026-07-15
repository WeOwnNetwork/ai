# dev-weown-devbox - Main Infrastructure
# Managed by OpenTofu
#
# Shared multi-user developer machine. NOT a web app: no Caddy, no compose web
# service, no inbound 80/443. The only inbound port is SSH (22). Each team
# member SSHes into their OWN account (provisioned by ansible/deploy.yml);
# root is reachable ONLY via the break-glass admin key (var.ssh_key_fingerprint).

resource "digitalocean_droplet" "devbox" {
  name       = "dev-weown-devbox"
  image      = var.droplet_image
  size       = var.droplet_size
  region     = var.region
  monitoring = true
  backups    = var.enable_skinny_backups ? false : true

  # Break-glass admin key only. Team members get per-user accounts + their own
  # authorized_keys via ansible/deploy.yml — they never use this key.
  ssh_keys = [var.ssh_key_fingerprint]

  # Path C: thin first-boot bootstrap only. The app layer (per-user accounts,
  # SSH membership, Zed setup, dev toolchain, backups) is owned by
  # ansible/deploy.yml so onboarding/offboarding never requires `tofu taint`.
  # Pass EXACTLY the keys referenced by templates/cloud-init.yaml.
  user_data = templatefile("${path.module}/templates/cloud-init.yaml", {
    project_name            = "dev_weown_devbox"
    hostname                = var.domain
    timezone                = var.timezone
    infisical_client_id     = var.infisical_client_id
    infisical_client_secret = var.infisical_client_secret
    infisical_project_id    = var.infisical_project_id
    infisical_environment   = var.infisical_environment
  })

  # Base tags. Feature tags + commit tag are added at runtime by:
  #   - scripts/tag-droplet.sh (helper, invoked by ansible deploy)
  #   - ansible/deploy.yml (adds skinny-backup + commit-<sha>)
  # See docs/INFRA_BOOTSTRAP_PATTERN.md "DO tag taxonomy" for the full scheme.
  # `ignore_changes = [tags]` prevents tofu apply from reverting runtime-added
  # tags on subsequent runs; `ignore_changes = [user_data]` keeps a member edit
  # (members.yml + re-run ansible) from forcing a droplet replacement.
  tags = ["dev-weown-devbox", "devbox", "dev", "weown-ai"]

  lifecycle {
    ignore_changes = [user_data, tags]
  }
}

# Reserved IP gives the box a stable SSH endpoint that survives droplet
# rebuilds, so members' SSH configs (and Zed remote hosts) never have to change.
resource "digitalocean_reserved_ip" "devbox" {
  region = var.region
}

resource "digitalocean_reserved_ip_assignment" "devbox" {
  ip_address = digitalocean_reserved_ip.devbox.ip_address
  droplet_id = digitalocean_droplet.devbox.id
}

# trivy:ignore:AVD-DIG-0002 SSH (22) from the internet is accepted by design: auth is key-only
#   (PasswordAuthentication no), every member has their own non-root account, root is
#   prohibit-password (break-glass key only), and the operator is expected to pin
#   var.ssh_source_cidrs to the team's IPs/VPN in production (default is wide-open).
# trivy:ignore:AVD-DIG-0003 Unrestricted egress is required: OS/security updates (apt), the
#   Infisical API (secret fetch + Layer 2 rotation), Zed remote-server downloads, NodeSource /
#   OpenTofu / doctl / pipx installers, git/package registries, OpenRouter, and DO Spaces backups.
resource "digitalocean_firewall" "devbox" {
  name        = "dev-weown-devbox-fw"
  droplet_ids = [digitalocean_droplet.devbox.id]

  # SSH — the ONLY inbound port. Restrict via var.ssh_source_cidrs (default is
  # wide-open; production should pin to team IPs/VPN). No 80/443: this is not a
  # web server.
  #trivy:ignore:AVD-DIG-0001  # SSH (22) inbound accepted by design: restricted to var.ssh_source_cidrs in prod, key-only auth (PasswordAuthentication no)
  inbound_rule {
    protocol         = "tcp"
    port_range       = "22"
    source_addresses = var.ssh_source_cidrs
  }

  # All outbound TCP
  #trivy:ignore:AVD-DIG-0003  # Unrestricted egress required: OS/security updates (apt), Infisical, DO Spaces, container registries
  outbound_rule {
    protocol              = "tcp"
    port_range            = "1-65535"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  # All outbound UDP
  #trivy:ignore:AVD-DIG-0003  # Unrestricted egress required: DNS + NTP + WireGuard/Tailscale
  outbound_rule {
    protocol              = "udp"
    port_range            = "1-65535"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  tags = ["dev-weown-devbox"]
}
