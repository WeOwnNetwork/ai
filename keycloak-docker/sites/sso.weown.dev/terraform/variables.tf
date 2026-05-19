# sso - Terraform Variables
# Managed by OpenTofu

variable "project_name" {
  description = "Project name (lowercase, hyphens allowed)"
  type        = string
}

variable "domain" {
  description = "Primary domain for Keycloak"
  type        = string
}

variable "region" {
  description = "DigitalOcean region slug"
  type        = string
  default     = "nyc3"
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
  description = "SSH key fingerprint for droplet access"
  type        = string
}

variable "minimus_token" {
  description = "DigitalOcean API token"
  type        = string
  sensitive   = true
}

variable "keycloak_image" {
  description = "Keycloak Docker image"
  type        = string
  default     = "reg.mini.dev/keycloak:24.0"
}

variable "caddy_image" {
  description = "Caddy Docker image"
  type        = string
  default     = "reg.mini.dev/caddy:2"
}

variable "postgres_version" {
  description = "PostgreSQL version"
  type        = string
  default     = "16"
}

variable "db_name" {
  description = "PostgreSQL database name"
  type        = string
  default     = "keycloak"
}

variable "db_user" {
  description = "PostgreSQL user"
  type        = string
  default     = "keycloak"
}

variable "db_password" {
  description = "PostgreSQL password"
  type        = string
  sensitive   = true
}

variable "db_root_password" {
  description = "PostgreSQL root password"
  type        = string
  sensitive   = true
}

variable "keycloak_admin_username" {
  description = "Keycloak admin username"
  type        = string
  default     = "admin"
}

variable "keycloak_admin_password" {
  description = "Keycloak admin password"
  type        = string
  sensitive   = true
}

variable "enable_infisical" {
  description = "Enable Infisical secrets management"
  type        = bool
  default     = false
}

variable "infisical_token" {
  description = "Infisical API token"
  type        = string
  sensitive   = true
  default     = ""
}

variable "infisical_project_id" {
  description = "Infisical project ID"
  type        = string
  default     = ""
}

variable "infisical_environment" {
  description = "Infisical environment slug"
  type        = string
  default     = "prod"
}

variable "enable_monitoring" {
  description = "Enable DigitalOcean monitoring alerts"
  type        = bool
  default     = true
}

variable "alert_email" {
  description = "Email for monitoring alerts"
  type        = string
  default     = "alerts@example.com"
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

# =============================================================================
# DigitalOcean Spaces (Terraform State Backend)
# =============================================================================

variable "spaces_access_key" {
  description = "DigitalOcean Spaces access key"
  type        = string
  sensitive   = true
}

variable "spaces_secret_key" {
  description = "DigitalOcean Spaces secret key"
  type        = string
  sensitive   = true
}

variable "spaces_encryption_key" {
  description = "DigitalOcean Spaces SSE-C encryption key (32-byte AES-256, base64)"
  type        = string
  sensitive   = true
}
