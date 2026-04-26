# sso - Terraform Backend Configuration
# State is stored in DigitalOcean Spaces for team sharing

terraform {
  backend "s3" {
    endpoint        = "https://atl1.digitaloceanspaces.com"
    bucket         = "weown-terraform-state"
    key            = "sso/sso.tfstate"
    region         = "us-east-1"
    encrypt        = true
    acl            = "private"
    # SSE-C encryption with customer-provided key
    # This key should be stored in Infisical with exec-only access for executives
    sse_customer_key = var.spaces_encryption_key

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

variable "spaces_encryption_key" {
  description = "DigitalOcean Spaces SSE-C encryption key (32-byte AES-256)"
  type        = string
  sensitive   = true
}
