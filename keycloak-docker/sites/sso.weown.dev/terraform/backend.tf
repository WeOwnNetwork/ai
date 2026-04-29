# sso - Terraform Backend Configuration
# State is stored in DigitalOcean Spaces for team sharing
# Bucket: weown-dev-backup
# Path: sso/sso.tfstate
#
# REQUIRED: Pass credentials via init.sh or -backend-config flags:
#   access_key           → DO Spaces access key
#   secret_key           → DO Spaces secret key
#   sse_customer_key     → SSE-C encryption key (32-byte AES-256, base64)
#
# Usage:
#   ./init.sh            # Reads creds from terraform.tfvars
#   tofu plan
#   tofu apply

terraform {
  backend "s3" {
    endpoint = "https://atl1.digitaloceanspaces.com"
    bucket   = "weown-dev-backup"
    key      = "sso/sso.tfstate"
    region   = "us-east-1"
    encrypt  = true
    acl      = "private"

    # Required for DO Spaces (S3-compatible but not AWS)
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_requesting_account_id  = true
    skip_region_validation      = true
    skip_s3_checksum            = true
  }
}
