# supabase-dev - Terraform State Backend
#
# Remote state on DigitalOcean Spaces (S3-compatible).
# Bucket policy: server-side encryption + private ACL + versioning.
#
# State key namespaced by project_name to avoid collisions across
# sibling deployments rendered from the same template.

terraform {
  backend "s3" {
    endpoint = "https://atl1.digitaloceanspaces.com"
    bucket   = "weown-tools-state"
    key      = "supabase-dev/supabase-dev.tfstate"
    region   = "us-east-1"
    encrypt  = true
    acl      = "private"

    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_requesting_account_id  = true
    skip_region_validation      = true
    skip_s3_checksum            = true
  }
}
