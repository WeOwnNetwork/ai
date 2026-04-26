# sso - Terraform Backend Configuration
# State is stored in DigitalOcean Spaces for team sharing

terraform {
  backend "s3" {
    endpoint        = "https://nyc3.digitaloceanspaces.com"
    bucket         = "weown-terraform-state"
    key            = "sso/sso.tfstate"
    region         = "us-east-1"
    encrypt        = true
    acl            = "private"
    # SSE encryption with customer-provided key (optional)
    # kms_key_id     = "your-kms-key-id"

    # DigitalOcean Spaces credentials (from environment or Infisical)
    access_key     = var.spaces_access_key
    secret_key     = var.spaces_secret_key

    # Locking via Spaces object locking
    lock           = true
    lock_timeout   = 300
  }
}

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
