# {{ project_name }} - Provider Configuration

terraform {
  required_version = ">= 1.5"
  # Compatible with OpenTofu (tofu) and Terraform

  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.36"
    }
  }
}

provider "digitalocean" {
  token = var.do_token
}
