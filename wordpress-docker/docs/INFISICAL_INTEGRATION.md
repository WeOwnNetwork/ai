# Infisical Integration

This document describes how to integrate Infisical secrets management with the WordPress Docker deployments.

## Overview

Infisical provides centralized secrets management, allowing you to:

- Store database credentials securely outside of version control
- Rotate credentials without redeploying infrastructure
- Audit access to sensitive values
- Sync secrets across multiple environments

## Architecture

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   Developer     │────▶│    Infisical    │◀────│   Cloud-Init    │
│   (local)       │     │    (SaaS/Self)  │     │   (bootstrap)   │
└─────────────────┘     └─────────────────┘     └─────────────────┘
                              │
                              ▼
                        ┌─────────────────┐
                        │   .env file     │
                        │   (on droplet)  │
                        └─────────────────┘
                              │
                              ▼
                        ┌─────────────────┐
                        │  Docker Stack   │
                        │  (WordPress)    │
                        └─────────────────┘
```

## Setup

### 1. Create Infisical Project

1. Log in to [Infisical](https://app.infisical.com) or your self-hosted instance
2. Create a new project for your WordPress site
3. Add the following secrets:

| Secret Name | Description | Example |
|-------------|-------------|---------|
| `MYSQL_DATABASE` | WordPress database name | `wordpress` |
| `MYSQL_USER` | WordPress database user | `wordpress` |
| `MYSQL_PASSWORD` | WordPress database password | `<strong-password>` |
| `MYSQL_ROOT_PASSWORD` | MySQL root password | `<strong-root-password>` |
| `WP_IMAGE` | WordPress Docker image | `reg.mini.dev/1923/wordpress-fluentsmtp:latest` |
| `CADDY_IMAGE` | Caddy Docker image | `reg.mini.dev/caddy:2` |
| `DOMAIN` | Site domain | `example.com` |

### 2. Create Universal Auth Token

1. Navigate to Project Settings → Machine Identities
2. Create a new Machine Identity
3. Add Universal Auth method
4. Copy the Client ID and Client Secret
5. Generate a token using the CLI:

```bash
infisical login --method=universal-auth \
  --client-id=<client-id> \
  --client-secret=<client-secret>
```

### 3. Configure Terraform

In `terraform.tfvars`:

```hcl
enable_infisical      = true
infisical_token       = "st.xxxxxxxxxxxx"
infisical_project_id  = "your-project-id"
infisical_environment = "prod"
```

## Cloud-Init Integration

When `enable_infisical` is true, the cloud-init script will:

1. Install the Infisical CLI
2. Authenticate using the Universal Auth token
3. Export secrets to the `.env` file
4. Start the Docker stack with the injected secrets

### Example Cloud-Init Additions

```yaml
runcmd:
  # Install Infisical CLI
  - curl -1sLf 'https://dl.cloudsmith.io/public/infisical/infisical-cli/setup.deb.sh' | sudo -E bash
  - apt-get update && apt-get install -y infisical

  # Export secrets to .env
  - |
    infisical export \
      --token="${infisical_token}" \
      --projectId="${infisical_project_id}" \
      --env="${infisical_environment}" \
      --format=dotenv > /opt/myproject/.env
```

## Credential Rotation

### Zero-Downtime Rotation

1. Update the secret value in Infisical
2. SSH to the droplet and re-export:

```bash
infisical export \
  --token="$INFISICAL_TOKEN" \
  --projectId="$PROJECT_ID" \
  --env="prod" \
  --format=dotenv > /opt/myproject/.env

cd /opt/myproject
docker compose down && docker compose up -d
```

### Automated Rotation Script

```bash
#!/usr/bin/env bash
# rotate-credentials.sh
set -euo pipefail

APP_DIR="/opt/myproject"
INFISICAL_TOKEN="${INFISICAL_TOKEN:-}"
PROJECT_ID="${PROJECT_ID:-}"

# Re-export secrets
infisical export \
  --token="$INFISICAL_TOKEN" \
  --projectId="$PROJECT_ID" \
  --env="prod" \
  --format=dotenv > "$APP_DIR/.env"

# Restart containers with new credentials
cd "$APP_DIR"
docker compose down
docker compose up -d

echo "Credentials rotated successfully"
```

## Security Best Practices

1. **Token Scope**: Use minimal scopes for Machine Identity tokens
2. **Token Rotation**: Rotate Infisical tokens periodically
3. **Audit Logs**: Enable and review Infisical audit logs
4. **IP Allowlist**: Restrict token usage to droplet IP if possible
5. **Environment Isolation**: Use separate Infisical environments for staging/prod

## Troubleshooting

### Token Authentication Failed

```bash
# Verify token is valid
infisical login --method=universal-auth --token="$INFISICAL_TOKEN"

# Check token permissions
infisical projects list
```

### Secrets Not Exported

```bash
# Manual export with debug output
infisical export \
  --token="$INFISICAL_TOKEN" \
  --projectId="$PROJECT_ID" \
  --env="prod" \
  --format=dotenv \
  --debug
```

### Docker Not Reading New .env

```bash
# Force recreate containers
docker compose down
docker compose up -d --force-recreate
```

## References

- [Infisical Documentation](https://infisical.com/docs)
- [Universal Auth](https://infisical.com/docs/documentation/platform/identities/universal-auth)
- [CLI Reference](https://infisical.com/docs/cli/overview)
