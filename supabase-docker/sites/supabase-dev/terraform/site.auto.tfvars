# supabase-dev - Site config (auto-loaded by terraform/tofu)
#
# `*.auto.tfvars` files are auto-loaded by terraform/tofu, so nothing to
# copy or symlink. This file holds ONLY non-sensitive site-specific values
# rendered by copier: domain, region, images, feature toggles, backup
# destination, monitoring thresholds, etc.
#
# What is NOT here (and why):
#   - do_token, ssh_key_fingerprint, spaces_access_key, spaces_secret_key,
#     spaces_encryption_key, infisical_client_id, infisical_client_secret,
#     alert_email — these are sensitive and are injected as TF_VAR_* by
#     itofu.sh from the `<bootstrap-project>` Infisical project (workflow 1),
#     OR filled into terraform.tfvars by hand from terraform.tfvars.example
#     (workflow 2). See terraform.tfvars.example for details.
#
# You CAN commit this file to git — it contains no secrets.

# =============================================================================
# Site Configuration
# =============================================================================

domain       = "supabase-dev.weown.tools"
region       = "atl1"
droplet_size = "s-4vcpu-8gb-amd"

# CIDRs allowed to SSH (port 22). PRODUCTION: restrict to admin IP/32 or VPN range.
ssh_source_cidrs = ["0.0.0.0/0"]

# Droplet OS image (Ubuntu 24.04 LTS recommended)
droplet_image = "ubuntu-24-04-x64"

# =============================================================================
# Container Images
# =============================================================================

postgres_image   = "supabase/postgres:15.6.1.115"
postgrest_image  = "postgrest/postgrest:v12.2.0"
gotrue_image     = "supabase/gotrue:v2.158.1"
realtime_image   = "supabase/realtime:v2.30.34"
studio_image     = "supabase/studio:2026.06.29-sha-20290c7"
caddy_image      = "reg.mini.dev/caddy:2"
postgres_version = "16"

# =============================================================================
# Supabase Feature Toggles
# =============================================================================

enable_pgvector = true
enable_studio   = true
enable_realtime = true

# =============================================================================
# Database (non-secret config; passwords live in Infisical <runtime-project>)
# =============================================================================

db_name = "supabase"
db_user = "postgres"

# =============================================================================
# Infisical project + env (the droplet reads app secrets from here)
# =============================================================================

infisical_project_id  = "6046a51c-ea7e-433d-a275-fa2b4174ba27"
infisical_environment = "dev"

# =============================================================================
# Skinny Backup Configuration
# =============================================================================

enable_skinny_backups = true
backup_remote_storage = "do-spaces"

# DigitalOcean Spaces bucket for remote backups (only if backup_remote_storage = "do-spaces").
# The Spaces keys used by the backup script live in the <runtime-project> Infisical
# project (SPACES_ACCESS_KEY, SPACES_SECRET_KEY), separate from the state
# bucket creds. The backup script fetches them via `infisical run`.
backup_do_spaces_bucket = "weown-prod-backups"
backup_do_spaces_region = "atl1"

# =============================================================================
# Monitoring (thresholds only — alert_email is sensitive, TF_VAR_alert_email)
# =============================================================================

enable_monitoring      = false
cpu_alert_threshold    = 80
memory_alert_threshold = 85
disk_alert_threshold   = 80
