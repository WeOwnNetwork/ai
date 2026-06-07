#!/usr/bin/env bash
# deploy-new-site.sh — Automated site deployment with tiered Infisical security
#
# This script automates the complete deployment workflow for new sites:
# 1. Validates inputs and checks naming conventions
# 2. Creates Infisical project using Tier 1 Machine Identity
# 3. Generates and pushes secrets to the new project
# 4. Creates site-specific Machine Identity (Tier 2)
# 5. Renders site from template using copier
# 6. Provisions infrastructure with tofu
# 7. Deploys application with ansible
# 8. Validates deployment and generates report
#
# Security Model:
# - Tier 1 MI: High privilege, limited scope (can create projects, cannot access existing ones)
# - Tier 2 MI: Low privilege, site-scoped (can only read its own project)
# - Layer 2 rotation: Tier 2 MI credentials rotated on first boot
#
# Usage:
#   ./deploy-new-site.sh \
#     --template keycloak-docker \
#     --site-name sso \
#     --domain sso.weown.dev \
#     --admin-email admin@weown.dev \
#     [--auto]           # Skip human review checkpoints
#     [--dry-run]        # Preview actions without executing
#     [--skip-infra]     # Skip infrastructure provisioning
#     [--skip-deploy]    # Skip application deployment
#
# Prerequisites:
# - infisical CLI installed and authenticated
# - copier installed (pip install copier)
# - tofu installed
# - ansible installed
# - doctl authenticated
# - Tier 1 MI credentials in operator-tools Infisical project
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
LOG_FILE="$REPO_ROOT/deploy.log"

# Cleanup trap — runs on any error or script exit
# Warns about orphaned resources and cleans up temp files
cleanup() {
  local exit_code=$?
  if [[ $exit_code -ne 0 ]]; then
    echo "" >&2
    echo "===================================================================" >&2
    echo "  Deployment failed (exit code: $exit_code)" >&2
    echo "===================================================================" >&2
    echo "" >&2
    echo "  Possible orphaned resources to clean up manually:" >&2
    if [[ -n "${PROJECT_ID:-}" ]]; then
      echo "  - Infisical project: $PROJECT_ID" >&2
    fi
    if [[ -n "${SITE_DIR:-}" && -d "${SITE_DIR:-}" ]]; then
      echo "  - Site directory: $SITE_DIR" >&2
    fi
    if [[ -n "${DROPLET_IP:-}" ]]; then
      echo "  - Droplet IP: $DROPLET_IP (check DigitalOcean dashboard)" >&2
    fi
    echo "" >&2
    echo "  Tier 1 credentials have been unset from this shell." >&2
    echo "===================================================================" >&2
  fi
  # Always clean up temp files
  rm -f "${REPO_ROOT}/tfplan" 2>/dev/null || true
}
trap cleanup EXIT

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
  echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*" | tee -a "$LOG_FILE"
}

success() {
  echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅${NC} $*" | tee -a "$LOG_FILE"
}

warn() {
  echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️${NC}  $*" | tee -a "$LOG_FILE"
}

error() {
  echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌${NC} $*" | tee -a "$LOG_FILE"
}

# Parse arguments
TEMPLATE=""
SITE_NAME=""
DOMAIN=""
ADMIN_EMAIL=""
AUTO_MODE=false
DRY_RUN=false
SKIP_INFRA=false
SKIP_DEPLOY=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --template) TEMPLATE="$2"; shift 2 ;;
    --site-name) SITE_NAME="$2"; shift 2 ;;
    --domain) DOMAIN="$2"; shift 2 ;;
    --admin-email) ADMIN_EMAIL="$2"; shift 2 ;;
    --auto) AUTO_MODE=true; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    --skip-infra) SKIP_INFRA=true; shift ;;
    --skip-deploy) SKIP_DEPLOY=true; shift ;;
    *) error "Unknown option: $1"; exit 1 ;;
  esac
done

# Validate required arguments
if [[ -z "$TEMPLATE" || -z "$SITE_NAME" || -z "$DOMAIN" || -z "$ADMIN_EMAIL" ]]; then
  echo "Usage: $0 --template <template> --site-name <name> --domain <domain> --admin-email <email> [options]"
  echo ""
  echo "Required:"
  echo "  --template      Template directory name (e.g., keycloak-docker)"
  echo "  --site-name     Site name (e.g., sso, auth)"
  echo "  --domain        Domain for the site (e.g., sso.weown.dev)"
  echo "  --admin-email   Admin email address"
  echo ""
  echo "Options:"
  echo "  --auto          Skip human review checkpoints"
  echo "  --dry-run       Preview actions without executing"
  echo "  --skip-infra    Skip infrastructure provisioning"
  echo "  --skip-deploy   Skip application deployment"
  exit 1
fi

# Validate template exists
TEMPLATE_DIR="$REPO_ROOT/$TEMPLATE"
if [[ ! -d "$TEMPLATE_DIR" ]]; then
  error "Template not found: $TEMPLATE_DIR"
  exit 1
fi

# Generate project name
PROJECT_NAME="${SITE_NAME}-${TEMPLATE%%-docker}"
SITE_DIR="$REPO_ROOT/$TEMPLATE/sites/$SITE_NAME"

log "Starting deployment: $PROJECT_NAME"
log "Template: $TEMPLATE"
log "Site name: $SITE_NAME"
log "Domain: $DOMAIN"
log "Admin email: $ADMIN_EMAIL"
log "Auto mode: $AUTO_MODE"
log "Dry run: $DRY_RUN"
echo ""

# Phase 1: Validation
log "Phase 1: Validation"

# Check naming conventions
if [[ ! "$SITE_NAME" =~ ^[a-z0-9-]+$ ]]; then
  error "Site name must be lowercase alphanumeric with hyphens: $SITE_NAME"
  exit 1
fi

if [[ ! "$DOMAIN" =~ ^[a-z0-9.-]+\.[a-z]{2,}$ ]]; then
  error "Invalid domain format: $DOMAIN"
  exit 1
fi

# Check if site already exists
if [[ -d "$SITE_DIR" ]]; then
  error "Site already exists: $SITE_DIR"
  exit 1
fi

success "Validation passed"
echo ""

# Phase 2: Infisical Setup
log "Phase 2: Infisical Setup"

if [[ "$DRY_RUN" == "true" ]]; then
  log "[DRY RUN] Would create Infisical project: $PROJECT_NAME"
  log "[DRY RUN] Would generate secrets (JWT_SECRET, etc.)"
  log "[DRY RUN] Would create site Machine Identity"
else
  # Check if infisical CLI is available
  if ! command -v infisical &>/dev/null; then
    error "infisical CLI not found. Install: curl -fsSL https://infisical.com/install-cli.sh | bash"
    exit 1
  fi

  # Check if authenticated
  if ! infisical login --method=universal-auth --silent &>/dev/null 2>&1; then
    error "Not authenticated to Infisical. Run: infisical login"
    exit 1
  fi

  # Get Tier 1 MI credentials from operator-tools project
  log "Retrieving Tier 1 MI credentials from operator-tools project..."
  TIER1_CLIENT_ID=$(infisical secrets get TIER1_MI_CLIENT_ID --projectId=operator-tools --env=prod --plain 2>/dev/null || echo "")
  TIER1_CLIENT_SECRET=$(infisical secrets get TIER1_MI_CLIENT_SECRET --projectId=operator-tools --env=prod --plain 2>/dev/null || echo "")

  if [[ -z "$TIER1_CLIENT_ID" || -z "$TIER1_CLIENT_SECRET" ]]; then
    error "Tier 1 MI credentials not found in operator-tools project"
    error "Please add TIER1_MI_CLIENT_ID and TIER1_MI_CLIENT_SECRET to operator-tools project"
    exit 1
  fi

  # Login with Tier 1 MI
  log "Authenticating with Tier 1 Machine Identity..."
  export INFISICAL_CLIENT_ID="$TIER1_CLIENT_ID"
  export INFISICAL_CLIENT_SECRET="$TIER1_CLIENT_SECRET"

  if ! infisical login --method=universal-auth --silent &>/dev/null 2>&1; then
    error "Failed to authenticate with Tier 1 MI"
    exit 1
  fi

  # Create Infisical project
  log "Creating Infisical project: $PROJECT_NAME"
  PROJECT_ID=$(infisical projects create --name="$PROJECT_NAME" --json 2>/dev/null | jq -r '.id' || echo "")

  if [[ -z "$PROJECT_ID" ]]; then
    error "Failed to create Infisical project"
    exit 1
  fi

  success "Created Infisical project: $PROJECT_ID"

  # Generate secrets
  log "Generating secrets..."
  JWT_SECRET=$(openssl rand -hex 32)

  # Push secrets to project
  log "Pushing secrets to project..."
  infisical secrets set JWT_SECRET="$JWT_SECRET" --projectId="$PROJECT_ID" --env=prod --silent
  infisical secrets set ADMIN_EMAIL="$ADMIN_EMAIL" --projectId="$PROJECT_ID" --env=prod --silent

  # Get shared secrets from operator-tools
  SPACES_ACCESS_KEY=$(infisical secrets get SPACES_ACCESS_KEY --projectId=operator-tools --env=prod --plain 2>/dev/null || echo "")
  SPACES_SECRET_KEY=$(infisical secrets get SPACES_SECRET_KEY --projectId=operator-tools --env=prod --plain 2>/dev/null || echo "")

  if [[ -n "$SPACES_ACCESS_KEY" && -n "$SPACES_SECRET_KEY" ]]; then
    infisical secrets set SPACES_ACCESS_KEY="$SPACES_ACCESS_KEY" --projectId="$PROJECT_ID" --env=prod --silent
    infisical secrets set SPACES_SECRET_KEY="$SPACES_SECRET_KEY" --projectId="$PROJECT_ID" --env=prod --silent
    success "Pushed shared Spaces credentials"
  fi

  # Create site Machine Identity (Tier 2)
  log "Creating site Machine Identity (Tier 2)..."
  MI_OUTPUT=$(infisical identities create --projectId="$PROJECT_ID" --name="$PROJECT_NAME-mi" --json 2>/dev/null || echo "{}")
  MI_CLIENT_ID=$(echo "$MI_OUTPUT" | jq -r '.clientId // empty')
  MI_CLIENT_SECRET=$(echo "$MI_OUTPUT" | jq -r '.clientSecret // empty')

  if [[ -z "$MI_CLIENT_ID" || -z "$MI_CLIENT_SECRET" ]]; then
    error "Failed to create site Machine Identity"
    exit 1
  fi

  success "Created site Machine Identity: $MI_CLIENT_ID"

  # Unset Tier 1 credentials from environment immediately after use
  # Prevents leakage via /proc/*/environ, child processes, or core dumps
  unset INFISICAL_CLIENT_ID INFISICAL_CLIENT_SECRET
  unset TIER1_CLIENT_ID TIER1_CLIENT_SECRET
  log "Tier 1 credentials unset from environment"

  # Checkpoint: Display credentials
  echo ""
  echo "==================================================================="
  echo "  Infisical Project Created"
  echo "==================================================================="
  echo "  Project ID: $PROJECT_ID"
  echo "  Site MI Client ID: $MI_CLIENT_ID"
  echo "  Site MI Client Secret: $MI_CLIENT_SECRET"
  echo ""
  echo "  ⚠️  Save the MI Client Secret securely — it will not be shown again"
  echo "==================================================================="
  echo ""

  if [[ "$AUTO_MODE" != "true" ]]; then
    read -p "Continue with deployment? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
      warn "Deployment cancelled by user"
      exit 0
    fi
  fi
fi

echo ""

# Phase 3: Site Rendering
log "Phase 3: Site Rendering"

if [[ "$DRY_RUN" == "true" ]]; then
  log "[DRY RUN] Would render site from template: $TEMPLATE"
  log "[DRY RUN] Would write site.conf with INFISICAL_PROJECT_ID=$PROJECT_ID"
else
  # Render site from template
  log "Rendering site from template..."
  cd "$REPO_ROOT/$TEMPLATE"

  copier copy . "sites/$SITE_NAME" \
    --data project_name="$PROJECT_NAME" \
    --data domain="$DOMAIN" \
    --data infisical_project_id="$PROJECT_ID" \
    --data infisical_environment="prod" \
    --defaults --trust --quiet

  cd "$REPO_ROOT"

  # Write site.conf
  log "Writing site.conf..."
  cat > "$SITE_DIR/site.conf" <<EOF
# $PROJECT_NAME — site-level operator config
INFISICAL_PROJECT_ID=$PROJECT_ID
INFISICAL_ENV=prod
EOF

  # Write terraform.tfvars — verify .gitignore covers it first
  log "Writing terraform.tfvars..."
  GITIGNORE_FILE="$SITE_DIR/terraform/.gitignore"
  if [[ -f "$GITIGNORE_FILE" ]]; then
    if ! grep -q 'terraform\.tfvars' "$GITIGNORE_FILE" 2>/dev/null; then
      warn "terraform.tfvars not in $GITIGNORE_FILE — adding it"
      echo "terraform.tfvars" >> "$GITIGNORE_FILE"
    fi
  else
    warn "No .gitignore found at $GITIGNORE_FILE — creating one"
    echo "terraform.tfvars" > "$GITIGNORE_FILE"
  fi
  cat > "$SITE_DIR/terraform/terraform.tfvars" <<EOF
# Generated by deploy-new-site.sh — DO NOT COMMIT
infisical_client_id     = "$MI_CLIENT_ID"
infisical_client_secret = "$MI_CLIENT_SECRET"
infisical_project_id    = "$PROJECT_ID"
infisical_environment   = "prod"
EOF

  success "Site rendered: $SITE_DIR"
fi

echo ""

# Phase 4: Infrastructure Provisioning
if [[ "$SKIP_INFRA" != "true" ]]; then
  log "Phase 4: Infrastructure Provisioning"

  if [[ "$DRY_RUN" == "true" ]]; then
    log "[DRY RUN] Would run: tofu init"
    log "[DRY RUN] Would run: tofu plan"
    log "[DRY RUN] Would run: tofu apply"
  else
    cd "$SITE_DIR/terraform"

    log "Initializing tofu..."
    tofu init -input=false

    log "Planning infrastructure..."
    tofu plan -out=tfplan -input=false

    # Checkpoint: Display plan
    echo ""
    echo "==================================================================="
    echo "  Infrastructure Plan"
    echo "==================================================================="
    tofu show tfplan | head -50
    echo "  ... (truncated, see full plan above)"
    echo "==================================================================="
    echo ""

    if [[ "$AUTO_MODE" != "true" ]]; then
      read -p "Apply this plan? (y/n) " -n 1 -r
      echo
      if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        warn "Infrastructure provisioning cancelled by user"
        rm -f tfplan
        exit 0
      fi
    fi

    log "Applying infrastructure..."
    tofu apply -input=false tfplan

    # Extract droplet IP
    DROPLET_IP=$(tofu output -raw droplet_ip 2>/dev/null || echo "")

    if [[ -z "$DROPLET_IP" ]]; then
      error "Failed to extract droplet IP from tofu output"
      exit 1
    fi

    success "Infrastructure provisioned: $DROPLET_IP"

    # Wait for cloud-init to complete
    log "Waiting for cloud-init to complete (this may take 5-10 minutes)..."
    MAX_WAIT=600  # 10 minutes
    WAITED=0
    INTERVAL=30

    while [[ $WAITED -lt $MAX_WAIT ]]; do
      if ssh -o StrictHostKeyChecking=accept-new -o ConnectTimeout=5 "root@$DROPLET_IP" \
         "test -f /opt/${PROJECT_NAME//[^a-zA-Z0-9]/_}/.bootstrap-complete" 2>/dev/null; then
        success "Cloud-init completed"
        break
      fi
      sleep $INTERVAL
      WAITED=$((WAITED + INTERVAL))
      log "Waiting... ($WAITED/$MAX_WAIT seconds)"
    done

    if [[ $WAITED -ge $MAX_WAIT ]]; then
      error "Timeout waiting for cloud-init to complete"
      error "Check droplet logs: ssh root@$DROPLET_IP 'tail -100 /var/log/cloud-init-output.log'"
      exit 1
    fi

    # Clean up
    rm -f tfplan terraform.tfvars

    cd "$REPO_ROOT"
  fi

  echo ""
else
  log "Phase 4: Skipped (--skip-infra)"
  echo ""
fi

# Phase 5: Application Deployment
if [[ "$SKIP_DEPLOY" != "true" ]]; then
  log "Phase 5: Application Deployment"

  if [[ "$DRY_RUN" == "true" ]]; then
    log "[DRY RUN] Would run: ./site.sh deploy"
    log "[DRY RUN] Would validate deployment"
  else
    cd "$SITE_DIR"

    # Get droplet IP if not already set
    if [[ -z "${DROPLET_IP:-}" ]]; then
      cd terraform
      DROPLET_IP=$(tofu output -raw droplet_ip 2>/dev/null || echo "")
      cd ..
    fi

    if [[ -z "$DROPLET_IP" ]]; then
      error "Cannot determine droplet IP"
      exit 1
    fi

    log "Deploying application..."
    ./site.sh deploy

    # Validate deployment
    log "Validating deployment..."
    sleep 10  # Give services time to start

    if ./site.sh health; then
      success "Health check passed"
    else
      error "Health check failed"
      error "Check logs: ssh root@$DROPLET_IP 'docker compose logs'"
      exit 1
    fi

    cd "$REPO_ROOT"
  fi

  echo ""
else
  log "Phase 5: Skipped (--skip-deploy)"
  echo ""
fi

# Phase 6: Reporting
log "Phase 6: Reporting"

REPORT_FILE="$SITE_DIR/DEPLOYMENT_REPORT.md"

cat > "$REPORT_FILE" <<EOF
# Deployment Report: $PROJECT_NAME

**Generated:** $(date -u +"%Y-%m-%d %H:%M:%S UTC")

## Site Information

- **Site Name:** $SITE_NAME
- **Domain:** $DOMAIN
- **Template:** $TEMPLATE
- **Project Name:** $PROJECT_NAME

## Infrastructure

- **Droplet IP:** ${DROPLET_IP:-N/A}
- **Site Directory:** $SITE_DIR

## Infisical

- **Project ID:** ${PROJECT_ID:-N/A}
- **Environment:** prod
- **Machine Identity:** ${MI_CLIENT_ID:-N/A}

## Deployment Status

- **Infrastructure:** $([ "$SKIP_INFRA" == "true" ] && echo "Skipped" || echo "✅ Provisioned")
- **Application:** $([ "$SKIP_DEPLOY" == "true" ] && echo "Skipped" || echo "✅ Deployed")
- **Health Check:** $([ "$SKIP_DEPLOY" == "true" ] && echo "Skipped" || echo "✅ Passed")

## Next Steps

1. Point DNS A record for $DOMAIN to ${DROPLET_IP:-<droplet-ip>}
2. Verify HTTPS certificate is issued (automatic via Caddy)
3. Test application functionality
4. Update WORK_LOG.md with deployment details

## Support

- **Logs:** \`ssh root@${DROPLET_IP:-<ip>} 'docker compose logs'\`
- **Health:** \`./site.sh health\`
- **Backup:** \`./site.sh backup\`
- **Restore:** \`./site.sh restore <backup-name>\`
EOF

success "Deployment report generated: $REPORT_FILE"

echo ""
echo "==================================================================="
echo "  Deployment Complete"
echo "==================================================================="
echo "  Site: $PROJECT_NAME"
echo "  Domain: $DOMAIN"
echo "  Droplet IP: ${DROPLET_IP:-N/A}"
echo "  Infisical Project: ${PROJECT_ID:-N/A}"
echo ""
echo "  Next steps:"
echo "  1. Point DNS A record for $DOMAIN to ${DROPLET_IP:-<droplet-ip>}"
echo "  2. Verify HTTPS certificate is issued"
echo "  3. Test application functionality"
echo "  4. Review deployment report: $REPORT_FILE"
echo "==================================================================="

log "Deployment completed successfully"
