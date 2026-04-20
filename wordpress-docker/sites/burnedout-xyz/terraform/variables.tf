# burnedout-xyz - Input Variables

variable "do_token" {
  description = "DigitalOcean API token"
  type        = string
  sensitive   = true
}

variable "domain" {
  description = "Primary domain for the site"
  type        = string
  default     = "burnedout.xyz"
}

variable "domain_style" {
  description = "Domain style: 'apex' for root domain, 'www' for www subdomain"
  type        = string
  default     = "apex"
}

variable "region" {
  description = "DigitalOcean region slug"
  type        = string
  default     = "atl1"
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

variable "enable_wordfence_waf" {
  description = "Enable Wordfence WAF auto-configuration"
  type        = bool
  default     = true
}

variable "alert_email" {
  description = "Email address for monitoring alerts"
  type        = string
  default     = "alerts@weown.net"
}
