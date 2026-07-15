# sso - Terraform Backend Configuration
# Using local state for initial deployment
# Can migrate to remote state (DO Spaces) later

terraform {
  backend "local" {
    path = "terraform.tfstate"
  }
}
