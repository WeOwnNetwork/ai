# example.com - Input Variables

# =============================================================================
# DigitalOcean Authentication
# =============================================================================
variable "do_token" {
  description = "DigitalOcean API token (Custom Scopes: Droplet, Reserved IP, Firewall, Tag, Monitoring, SSH Key)"
  type        = string
  sensitive   = true
}

# =============================================================================
# Site Configuration
# =============================================================================
variable "domain" {
  description = "Primary domain for the site"
  type        = string
  default     = "example.com"
}

variable "domain_style" {
  description = "Domain style: 'apex' for root domain, 'www' for www subdomain with apex redirect"
  type        = string
  default     = "apex"
  validation {
    condition     = contains(["apex", "www"], var.domain_style)
    error_message = "domain_style must be 'apex' or 'www'"
  }
}

# Project Name (used for naming resources and folders)
variable "project_name" {
  description = "Project name used for droplet, tags, and /opt directory"
  type        = string
}

# =============================================================================
# Infrastructure
# =============================================================================
variable "region" {
  description = "DigitalOcean region slug"
  type        = string
  default     = "nyc3"
}

variable "droplet_size" {
  description = "Droplet size slug"
  type        = string
  default     = "s-2vcpu-2gb-amd"
}

variable "droplet_image" {
  description = "Droplet OS image slug"
  type        = string
  default     = "ubuntu-24-04-x64"
}

variable "ssh_key_fingerprint" {
  description = "Fingerprint of SSH key in your DigitalOcean account"
  type        = string
}

variable "reserved_ip" {
  description = "Existing reserved IP address to assign to the droplet"
  type        = string
}

variable "infisical_client_id" {
  description = "Infisical Universal Auth client ID"
  type        = string
  sensitive   = true
}

variable "infisical_client_secret" {
  description = "Infisical Universal Auth client secret"
  type        = string
  sensitive   = true
}

# =============================================================================
# Container Images
# =============================================================================
variable "minimus_token" {
  description = "Minimus registry token for pulling images from reg.mini.dev"
  type        = string
  sensitive   = true
}

variable "wp_image" {
  description = "WordPress Docker image"
  type        = string
  default     = "reg.mini.dev/wordpress:latest"
}

variable "caddy_image" {
  description = "Caddy Docker image"
  type        = string
  default     = "reg.mini.dev/caddy:2"
}

variable "mariadb_version" {
  description = "MariaDB version tag"
  type        = string
  default     = "11"
}

# =============================================================================
# Database Credentials
# =============================================================================
variable "mysql_database" {
  description = "WordPress MySQL database name"
  type        = string
  default     = "wordpress"
}

variable "mysql_user" {
  description = "WordPress MySQL user"
  type        = string
  default     = "wordpress"
}

variable "mysql_password" {
  description = "WordPress MySQL user password"
  type        = string
  sensitive   = true
}

variable "mysql_root_password" {
  description = "MySQL root password"
  type        = string
  sensitive   = true
}

# =============================================================================
# Security Features
# =============================================================================
variable "enable_wordfence_waf" {
  description = "Enable Wordfence WAF auto-configuration"
  type        = bool
  default     = true
}

# =============================================================================
# Infisical Integration
# =============================================================================
variable "enable_infisical" {
  description = "Enable Infisical secrets management"
  type        = bool
  default     = true
}

variable "infisical_token" {
  description = "Infisical Universal Auth token"
  type        = string
  sensitive   = true
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

variable "secret_rotation_version" {
  description = "Bump this value to force secret rotation through OpenTofu"
  type        = string
  default     = "initial"
}

variable "private_key_path" {
  description = "Path to SSH private key used by OpenTofu remote-exec"
  type        = string
}

# =============================================================================
# Monitoring
# =============================================================================
variable "alert_email" {
  description = "Email address for monitoring alerts"
  type        = string
  default     = "admin@example.com"
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
