# weown-ci-runner - Main Infrastructure (Gitea Actions runner)
# Managed by OpenTofu
#
# A runner executes pull-request code with a Docker daemon, which is
# root-equivalent on this host. So this droplet holds nothing else: no forge,
# no database, no other service's secrets.

resource "digitalocean_droplet" "runner" {
  name       = "weown-ci-runner"
  image      = var.droplet_image
  size       = var.droplet_size
  region     = var.region
  monitoring = true
  # Stateless: the only state is the runner's registration (re-registering is
  # one Infisical secret and a restart), so there is nothing worth a DO backup.
  backups = false

  ssh_keys = var.ssh_key_fingerprints

  user_data = templatefile("${path.module}/templates/cloud-init.yaml", {
    project_name            = "weown_ci_runner"
    infisical_client_id     = var.infisical_client_id
    infisical_client_secret = var.infisical_client_secret
    infisical_project_id    = var.infisical_project_id
    infisical_environment   = var.infisical_environment
  })

  tags = ["weown-ci-runner", "gitea-runner", "ci", "weown-ai"]

  lifecycle {
    ignore_changes = [user_data]
  }
}

resource "digitalocean_firewall" "runner" {
  name        = "weown-ci-runner-fw"
  droplet_ids = [digitalocean_droplet.runner.id]

  # Admin SSH only. The runner needs NO inbound port: it polls the forge outbound.
  # var.ssh_source_cidrs has no default (set in Infisical) and its validation refuses the world.
  inbound_rule {
    protocol         = "tcp"
    port_range       = "22"
    source_addresses = var.ssh_source_cidrs
  }

  # Outbound: the forge (HTTPS), image registries, apt and Infisical. CI jobs
  # fetch packages from arbitrary hosts, so outbound stays open.
  #trivy:ignore:AVD-DIG-0003  # a CI runner must reach registries/package mirrors it cannot enumerate
  outbound_rule {
    protocol              = "tcp"
    port_range            = "1-65535"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  #trivy:ignore:AVD-DIG-0003  # DNS and NTP
  outbound_rule {
    protocol              = "udp"
    port_range            = "1-65535"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  tags = ["weown-ci-runner"]
}
