# supabase-dev - Terraform Variables
# Managed by OpenTofu
#
# SECURITY NOTE: No application secrets (DB passwords, JWT_SECRET, ANON_KEY,
# SERVICE_ROLE_KEY, dashboard creds, etc.) are stored in terraform.tfvars.
# All application secrets live in Infisical and are injected at container
# runtime via `infisical run -- docker compose up -d`.
#
# The ONLY sensitive values in tfvars are:
#   - do_token                 (DigitalOcean API token — required by the DO provider)
#   - ssh_key_fingerprint      (public key fingerprint — non-secret identifier)
#   - infisical_client_id      (Machine Identity for runtime secret fetch)
#   - infisical_client_secret  (Machine Identity for runtime secret fetch)
#   - spaces_access_key        (terraform state backend creds — forwarded by init.sh)
#   - spaces_secret_key        (terraform state backend creds — forwarded by init.sh)
#   - spaces_encryption_key    (SSE-C key — forwarded by init.sh)

# =============================================================================
# Project Identity
# =============================================================================

variable "domain" {
  description = "Primary domain for Supabase (Studio UI + REST API + Realtime ws endpoint hang off subpaths or subdomains)"
  type        = string
}

# =============================================================================
# DigitalOcean Infrastructure
# =============================================================================
variable "region" {
  description = "DigitalOcean region slug"
  type        = string
  default     = "atl1"
}

variable "droplet_size" {
  description = "Droplet size (CPU/RAM). Supabase stack needs 8GB minimum for prod (Postgres + GoTrue + Realtime + Studio + PostgREST + Caddy)."
  type        = string
  default     = "s-4vcpu-8gb-amd"
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
  default = ["0.0.0.0/0"]
}

variable "do_token" {
  description = "DigitalOcean API token for the DO provider (Custom Scopes required: Droplet, Reserved IP, Firewall, Tag, Monitoring, SSH Key (read) - the SSH Key scope is needed because main.tf reads the fingerprint via digitalocean_ssh_key data source. Optional: Domain, if the digitalocean_record resource is used for A record automation)"
  type        = string
  sensitive   = true
}

# =============================================================================
# Container Images
# =============================================================================
variable "postgres_image" {
  description = "Supabase Postgres Docker image (bundles pgvector + extensions used by Pop schema)"
  type        = string
  default     = "supabase/postgres:15.6.1.115"
}

variable "postgrest_image" {
  description = "PostgREST Docker image (auto-generates REST API from Postgres schema)"
  type        = string
  default     = "postgrest/postgrest:v12.2.0"
}

variable "gotrue_image" {
  description = "GoTrue Docker image (JWT auth service — issues + verifies tokens used by RLS)"
  type        = string
  default     = "supabase/gotrue:v2.158.1"
}

variable "realtime_image" {
  description = "Realtime Docker image (WebSocket subscriptions to Postgres changes)"
  type        = string
  default     = "supabase/realtime:v2.30.34"
}

variable "studio_image" {
  description = "Supabase Studio admin UI Docker image"
  type        = string
  default     = "supabase/studio:2026.06.29-sha-20290c7"
}

variable "caddy_image" {
  description = "Caddy Docker image (TLS reverse proxy)"
  type        = string
  default     = "reg.mini.dev/caddy:2"
}

variable "postgres_version" {
  description = "PostgreSQL major version (informational — actual version pinned by postgres_image)"
  type        = string
  default     = "16"
}

# =============================================================================
# Supabase Feature Toggles
# =============================================================================
variable "enable_pgvector" {
  description = "Enable pgvector extension (vector embeddings for AI/RAG workloads on Pop interactions)"
  type        = bool
  default     = true
}

variable "enable_studio" {
  description = "Enable Supabase Studio admin UI"
  type        = bool
  default     = true
}

variable "enable_realtime" {
  description = "Enable Realtime service (WebSocket subscriptions on Pop tables)"
  type        = bool
  default     = true
}

# =============================================================================
# Database (non-secret config only — credentials live in Infisical)
# =============================================================================
variable "db_name" {
  description = "PostgreSQL database name (Pop schema lives inside)"
  type        = string
  default     = "supabase"
}

variable "db_user" {
  description = "PostgreSQL superuser (Supabase uses 'postgres' by convention; PostgREST connects as anon/authenticated roles)"
  type        = string
  default     = "postgres"
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
  default     = "dev"
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
# Skinny Backup Configuration
# =============================================================================
variable "enable_skinny_backups" {
  description = "Enable volume-based skinny backups (replaces DO automated backups; uses pg_dump for Postgres volume)"
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
  default     = false
}

variable "alert_email" {
  description = "Email for monitoring alerts"
  type        = string
  default     = "alerts@weown.net"
}

variable "cpu_alert_threshold" {
  description = "CPU usage alert threshold (%)"
  type        = number
  default     = 80
}

variable "memory_alert_threshold" {
  description = "Memory usage alert threshold (%)"
  type        = number
  default     = 85
}

variable "disk_alert_threshold" {
  description = "Disk usage alert threshold (%)"
  type        = number
  default     = 80
}
