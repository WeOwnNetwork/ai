# dev-weown-devbox - devbox OpenTofu Version Constraints
# Managed by OpenTofu

terraform {
  required_version = ">= 1.7.0"

  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.36"
    }
  }
}

provider "digitalocean" {
  token = var.minimus_token
}
