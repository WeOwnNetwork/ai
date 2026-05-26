# s004-anythingllm - Terraform Backend Configuration
# State is stored in DigitalOcean Spaces (S3-compatible) for team sharing
# with SSE-C encryption at rest.
#
# REQUIRED: Pass credentials via init.sh (preferred) or -backend-config flags:
#   access_key           → DO Spaces access key
#   secret_key           → DO Spaces secret key
#   sse_customer_key     → SSE-C encryption key (32-byte AES-256, base64)
#
# Backend config cannot reference Terraform variables (init runs before
# vars are evaluated). Use ./init.sh which forwards values from
# terraform.tfvars via `-backend-config` flags.
#
# Usage:
#   ./init.sh            # one-time per checkout, reads creds from terraform.tfvars
#   tofu plan
#   tofu apply

terraform {
  backend "s3" {
    endpoint = "https://atl1.digitaloceanspaces.com"
    bucket   = "weown-terraform-state"
    key      = "s004-anythingllm/s004-anythingllm.tfstate"
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
