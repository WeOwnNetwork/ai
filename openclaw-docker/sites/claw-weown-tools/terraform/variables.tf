# claw-weown-tools - Terraform Variables
# Managed by OpenTofu
#
# SECURITY NOTE: No application secrets (OPENCLAW_GATEWAY_TOKEN,
# OPENROUTER_API_KEY, SIGNOZ_INGESTION_KEY, API keys) are stored in
# terraform.tfvars. All application secrets live in Infisical and are
# injected at container runtime via `infisical run`.
#
# The ONLY sensitive values in tfvars are:
#   - minimus_token            → DigitalOcean API token (required by DO provider)
#   - ssh_key_fingerprint      → Public key fingerprint (non-secret identifier)
#   - infisical_client_id      → Machine Identity for runtime secret fetch
#   - infisical_client_secret  → Machine Identity secret for runtime secret fetch

# =============================================================================
# Project Identity
# =============================================================================
variable "project_name" {
  description = "Project name (lowercase, hyphens allowed)"
  type        = string
}

variable "domain" {
  description = "Primary domain for OpenClaw"
  type        = string
}

# =============================================================================
# DigitalOcean Infrastructure
# =============================================================================
variable "region" {
  description = "DigitalOcean region slug"
  type        = string
  default     = "nyc1"
}

variable "droplet_size" {
  description = "Droplet size (CPU/RAM)"
  type        = string
  default     = "s-2vcpu-4gb-amd"
}

variable "droplet_image" {
  description = "Droplet base image"
  type        = string
  default     = "ubuntu-24-04-x64"
}

variable "ssh_key_fingerprint" {
  description = "SSH key fingerprint for droplet access (non-secret public identifier)"
  type        = string
}

variable "ssh_source_cidrs" {
  description = "CIDR list allowed to reach port 22 — PRODUCTION: restrict to admin IP/32 or VPN range"
  type        = list(string)
  # `tojson` emits a valid JSON array (double-quoted strings) which HCL parses
  # as a list. Without it, Copier renders Python's list-repr ('a', 'b') and
  # `tofu plan` fails with "Invalid character" on the single quotes.
  default = ["0.0.0.0/0", "::/0"]
}

variable "minimus_token" {
  description = "DigitalOcean API token for the DO provider (Custom Scopes: Droplet, Reserved IP, Firewall, Tag, Monitoring)"
  type        = string
  sensitive   = true
}

# =============================================================================
# Terraform State Backend (DO Spaces) — forwarded by init.sh
# =============================================================================
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

# =============================================================================
# Container Images
# =============================================================================
variable "openclaw_image" {
  description = "OpenClaw Docker image (pin a specific tag, NOT :latest)"
  type        = string
  default     = "reg.mini.dev/mini_gylkcesroxy3i6lexniyg6jm2m3j3mzy/openclaw:2026.6.1"
}

variable "caddy_image" {
  description = "Caddy Docker image"
  type        = string
  default     = "reg.mini.dev/caddy:2"
}

variable "openclaw_internal_port" {
  description = "Internal port OpenClaw listens on (Caddy reverse-proxies to this)"
  type        = number
  default     = 18789
}

# =============================================================================
# Infisical Machine Identity (runtime secret injection)
# =============================================================================
variable "infisical_client_id" {
  description = "Infisical Machine Identity Client ID (grants droplet access to fetch secrets)"
  type        = string
  sensitive   = true
}

variable "infisical_client_secret" {
  description = "Infisical Machine Identity Client Secret (shown once at creation in Infisical dashboard)"
  type        = string
  sensitive   = true
}

variable "infisical_project_id" {
  description = "Infisical project ID containing this deployment's secrets"
  type        = string
}

variable "infisical_environment" {
  description = "Infisical environment slug (e.g., prod, staging)"
  type        = string
  default     = "prod"
}

# =============================================================================
# Skinny Backup Configuration
# =============================================================================
variable "enable_skinny_backups" {
  description = "Enable volume-based skinny backups (replaces DO automated backups)"
  type        = bool
  default     = true
}

variable "backup_remote_storage" {
  description = "Remote storage target for backup offloading"
  type        = string
  default     = "do-spaces"
}

variable "backup_do_spaces_bucket" {
  description = "DO Spaces bucket name for remote backups"
  type        = string
  default     = "weown-backups"
}

variable "backup_do_spaces_region" {
  description = "DO Spaces region slug"
  type        = string
  default     = "atl1"
}

# =============================================================================
# Monitoring
# =============================================================================
variable "enable_monitoring" {
  description = "Enable DigitalOcean monitoring alerts"
  type        = bool
  default     = true
}

variable "alert_email" {
  description = "Email for monitoring alerts"
  type        = string
  default     = "ops@weown.net"
}

variable "cpu_alert_threshold" {
  description = "CPU usage alert threshold (%)"
  type        = number
  default     = 80
}

variable "memory_alert_threshold" {
  description = "Memory usage alert threshold (%)"
  type        = number
  default     = 90
}

variable "disk_alert_threshold" {
  description = "Disk usage alert threshold (%)"
  type        = number
  default     = 85
}
