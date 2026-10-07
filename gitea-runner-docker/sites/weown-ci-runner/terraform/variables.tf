# weown-ci-runner - Terraform Variables
# Managed by OpenTofu
#
# Secrets arrive as TF_VAR_* from Infisical via ./itofu.sh (weown-tofu project,
# /infra/shared + /infra/sites/weown-ci-runner). Never in terraform.tfvars in git.

variable "region" {
  description = "DigitalOcean region slug"
  type        = string
  default     = "atl1"
}

variable "droplet_size" {
  description = "Droplet size (CPU/RAM). Every CI job runs here."
  type        = string
  default     = "s-2vcpu-4gb-amd"
}

variable "droplet_image" {
  description = "Droplet base image"
  type        = string
  default     = "ubuntu-24-04-x64"
}

variable "ssh_key_fingerprints" {
  description = "List of DO SSH key fingerprints for droplet access (non-secret public identifiers). Matches the SHARED weown-tofu /infra/shared var TF_VAR_ssh_key_fingerprints (json list)."
  type        = list(string)
}

variable "ssh_source_cidrs" {
  description = "CIDR list allowed to reach the admin SSH port (22): the ONLY inbound rule. No default and never in git (public repo): set TF_VAR_ssh_source_cidrs (json list) in weown-tofu /infra/sites/weown-ci-runner/."
  type        = list(string)

  validation {
    condition     = length(var.ssh_source_cidrs) > 0 && !contains(var.ssh_source_cidrs, "0.0.0.0/0") && !contains(var.ssh_source_cidrs, "::/0")
    error_message = "ssh_source_cidrs must name your admin IP/32 or VPN range, never the world: this host runs pull-request code."
  }
}

variable "do_token" {
  description = "DigitalOcean API token for the DO provider (Custom Scopes: Droplet, Firewall, Tag, Monitoring)"
  type        = string
  sensitive   = true
}

variable "infisical_client_id" {
  description = "Infisical Machine Identity Client ID for the runner's OWN project"
  type        = string
  sensitive   = true
}

variable "infisical_client_secret" {
  description = "Infisical Machine Identity Client Secret (v1; cloud-init rotates it to v2 on first boot)"
  type        = string
  sensitive   = true
}

variable "infisical_project_id" {
  description = "Infisical project ID holding GITEA_RUNNER_REGISTRATION_TOKEN and nothing else"
  type        = string
}

variable "infisical_environment" {
  description = "Infisical environment slug (e.g., prod)"
  type        = string
  default     = "prod"
}

variable "spaces_access_key" {
  description = "DigitalOcean Spaces access key for terraform state backend"
  type        = string
  sensitive   = true
}

variable "spaces_secret_key" {
  description = "DigitalOcean Spaces secret key for terraform state backend"
  type        = string
  sensitive   = true
}

variable "spaces_encryption_key" {
  description = "DigitalOcean Spaces SSE-C encryption key (32-byte AES-256, base64)"
  type        = string
  sensitive   = true
}

variable "enable_monitoring" {
  description = "Enable DigitalOcean monitoring alerts"
  type        = bool
  default     = true
}

variable "alert_email" {
  description = "A DO-verified email for monitoring alerts (TF_VAR_alert_email in weown-tofu /infra/shared)"
  type        = string
}

variable "cpu_alert_threshold" {
  description = "CPU usage alert threshold (%)"
  type        = number
  default     = 95
}

variable "memory_alert_threshold" {
  description = "Memory usage alert threshold (%)"
  type        = number
  default     = 90
}

variable "disk_alert_threshold" {
  description = "Disk usage alert threshold (%)"
  type        = number
  default     = 80
}
