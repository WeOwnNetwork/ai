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
#     --domain sso.example.com \
#     --admin-email admin@example.com \
#     [--auto]           # Skip human review checkpoints
#     [--dry-run]        # Preview actions without executing
#     [--skip-infra]     # Skip infrastructure provisioning
#     [--skip-deploy]    # Skip application deployment
#     [--skip-infisical] # Skip Infisical setup (requires env vars)
#
# Prerequisites:
# - infisical CLI installed and authenticated (unless using --skip-infisical)
# - copier installed (pip install copier)
# - tofu installed
# - ansible installed
# - jq installed (used to parse Infisical CLI JSON output)
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
LOG_FILE="$REPO_ROOT/deploy.log"

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
SKIP_INFISICAL=false
SKIP_IMAGE=false
SKIP_LLM_KEY=false

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
    --skip-infisical) SKIP_INFISICAL=true; shift ;;
    --skip-image) SKIP_IMAGE=true; shift ;;
    --skip-llm-key) SKIP_LLM_KEY=true; shift ;;
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
  echo "  --domain        Domain for the site (e.g., sso.example.com)"
  echo "  --admin-email   Admin email address"
  echo ""
  echo "Options:"
  echo "  --auto          Skip human review checkpoints"
  echo "  --dry-run       Preview actions without executing"
  echo "  --skip-infra    Skip infrastructure provisioning"
  echo "  --skip-deploy   Skip application deployment"
  echo "  --skip-infisical Skip Infisical setup (requires INFISICAL_PROJECT_ID, INFISICAL_CLIENT_ID, INFISICAL_CLIENT_SECRET)"
  echo "  --skip-image     (anythingllm) proceed without ANYTHINGLLM_IMAGE — instance will NOT boot until set"
  echo "  --skip-llm-key   (anythingllm) proceed without minting the OpenRouter key — instance will NOT boot until set"
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

if [[ "$SKIP_INFISICAL" == "true" ]]; then
  log "Phase 2: Skipped (--skip-infisical)"

  # Validate required environment variables
  if [[ -z "${INFISICAL_PROJECT_ID:-}" || -z "${INFISICAL_CLIENT_ID:-}" || -z "${INFISICAL_CLIENT_SECRET:-}" ]]; then
    error "When using --skip-infisical, the following environment variables are required:"
    error "  - INFISICAL_PROJECT_ID: existing Infisical project ID"
    error "  - INFISICAL_CLIENT_ID: existing Tier 2 MI client ID"
    error "  - INFISICAL_CLIENT_SECRET: existing Tier 2 MI client secret"
    exit 1
  fi

  # Use the provided environment variables
  PROJECT_ID="$INFISICAL_PROJECT_ID"
  MI_CLIENT_ID="$INFISICAL_CLIENT_ID"
  MI_CLIENT_SECRET="$INFISICAL_CLIENT_SECRET"

  # Unset env vars to prevent leakage to child processes (copier, tofu, ansible)
  unset INFISICAL_PROJECT_ID INFISICAL_CLIENT_ID INFISICAL_CLIENT_SECRET

  success "Using existing Infisical project: $PROJECT_ID"
  echo ""
elif [[ "$DRY_RUN" == "true" ]]; then
  log "[DRY RUN] Would create Infisical project: $PROJECT_NAME"
  log "[DRY RUN] Would generate secrets (JWT_SECRET, etc.)"
  log "[DRY RUN] Would create site Machine Identity"
  # Assign placeholder for dry-run to prevent unbound variable errors in Phase 3
  PROJECT_ID="dry-run-project-id"
  MI_CLIENT_ID="dry-run-client-id"
  MI_CLIENT_SECRET="dry-run-client-secret"
else
  # Check if infisical CLI is available
  if ! command -v infisical &>/dev/null; then
    error "infisical CLI not found. Install: curl -fsSL https://infisical.com/install-cli.sh | bash"
    exit 1
  fi

  # Check if authenticated — probe the stored session token; the previous
  # `infisical login --method=universal-auth` "check" ATTEMPTED a fresh MI
  # login (needs INFISICAL_UNIVERSAL_AUTH_* env vars) and always failed for
  # an interactively logged-in operator.
  if ! infisical user get token &>/dev/null; then
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
  # Authenticate with Tier 1 MI via API (documented, proven pattern)
  log "Authenticating with Tier 1 Machine Identity via API..."
  if ! command -v jq &>/dev/null; then
    error "jq not found. Install: apt install jq (Debian/Ubuntu) or brew install jq (macOS)"
    exit 1
  fi

  TIER1_TOKEN=$(curl -s -X POST https://app.infisical.com/api/v1/auth/universal-auth/login \
    -H "Content-Type: application/json" \
    -d "{\"clientId\":\"$TIER1_CLIENT_ID\",\"clientSecret\":\"$TIER1_CLIENT_SECRET\"}" \
    | jq -r '.accessToken // empty')

  if [[ -z "$TIER1_TOKEN" ]]; then
    error "Failed to authenticate with Tier 1 MI"
    exit 1
  fi
  log "Tier 1 MI authenticated"

  # Create Infisical project via API (POST /api/v1/projects)
  log "Creating Infisical project: $PROJECT_NAME"
  PROJECT_ID=$(curl -s -X POST https://app.infisical.com/api/v1/projects \
    -H "Authorization: Bearer $TIER1_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"name\":\"$PROJECT_NAME\"}" \
    | jq -r '.project.id // empty')

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

  # ADR-006: Generate duplicated secret names for multi-container stacks
  # WordPress needs MYSQL_PASSWORD + WORDPRESS_DB_PASSWORD (same value)
  # Keycloak needs POSTGRES_PASSWORD + KC_DB_PASSWORD (same value)
  if [[ "$TEMPLATE" == "wordpress-docker" ]]; then
    log "Generating duplicated secrets for WordPress..."
    MYSQL_PASSWORD=$(openssl rand -hex 32)
    infisical secrets set MYSQL_PASSWORD="$MYSQL_PASSWORD" --projectId="$PROJECT_ID" --env=prod --silent
    infisical secrets set WORDPRESS_DB_PASSWORD="$MYSQL_PASSWORD" --projectId="$PROJECT_ID" --env=prod --silent
    success "Pushed duplicated secrets: MYSQL_PASSWORD + WORDPRESS_DB_PASSWORD"
  elif [[ "$TEMPLATE" == "keycloak-docker" ]]; then
    log "Generating duplicated secrets for Keycloak..."
    POSTGRES_PASSWORD=$(openssl rand -hex 32)
    infisical secrets set POSTGRES_PASSWORD="$POSTGRES_PASSWORD" --projectId="$PROJECT_ID" --env=prod --silent
    infisical secrets set KC_DB_PASSWORD="$POSTGRES_PASSWORD" --projectId="$PROJECT_ID" --env=prod --silent
    success "Pushed duplicated secrets: POSTGRES_PASSWORD + KC_DB_PASSWORD"
  elif [[ "$TEMPLATE" == "gitea-docker" ]]; then
    # Gitea reads config from GITEA__section__KEY env vars (ADR-006: injected
    # in-container by infisical run). DB creds are duplicated so postgres and
    # gitea each see the env names they expect. SECRET_KEY / INTERNAL_TOKEN /
    # oauth2 JWT_SECRET are generated with gitea's own generator (INTERNAL_TOKEN
    # and JWT_SECRET have format requirements a plain hex string doesn't meet) —
    # via a throwaway container, nothing touches disk.
    log "Generating Gitea secrets..."
    if ! command -v docker &>/dev/null; then
      error "docker is required to generate Gitea secrets (gitea generate secret)"
      exit 1
    fi
    GITEA_GEN_IMAGE="${GITEA_GEN_IMAGE:-gitea/gitea:1.24}"
    POSTGRES_PASSWORD=$(openssl rand -hex 32)
    GITEA_SECRET_KEY=$(docker run --rm "$GITEA_GEN_IMAGE" gitea generate secret SECRET_KEY)
    GITEA_INTERNAL_TOKEN=$(docker run --rm "$GITEA_GEN_IMAGE" gitea generate secret INTERNAL_TOKEN)
    GITEA_JWT_SECRET=$(docker run --rm "$GITEA_GEN_IMAGE" gitea generate secret JWT_SECRET)
    if [[ -z "$GITEA_SECRET_KEY" || -z "$GITEA_INTERNAL_TOKEN" || -z "$GITEA_JWT_SECRET" ]]; then
      error "gitea generate secret produced empty output (image: $GITEA_GEN_IMAGE)"
      exit 1
    fi
    infisical secrets set POSTGRES_DB="gitea" --projectId="$PROJECT_ID" --env=prod --silent
    infisical secrets set POSTGRES_USER="gitea" --projectId="$PROJECT_ID" --env=prod --silent
    infisical secrets set POSTGRES_PASSWORD="$POSTGRES_PASSWORD" --projectId="$PROJECT_ID" --env=prod --silent
    infisical secrets set GITEA__database__USER="gitea" --projectId="$PROJECT_ID" --env=prod --silent
    infisical secrets set GITEA__database__PASSWD="$POSTGRES_PASSWORD" --projectId="$PROJECT_ID" --env=prod --silent
    infisical secrets set GITEA__security__SECRET_KEY="$GITEA_SECRET_KEY" --projectId="$PROJECT_ID" --env=prod --silent
    infisical secrets set GITEA__security__INTERNAL_TOKEN="$GITEA_INTERNAL_TOKEN" --projectId="$PROJECT_ID" --env=prod --silent
    infisical secrets set GITEA__oauth2__JWT_SECRET="$GITEA_JWT_SECRET" --projectId="$PROJECT_ID" --env=prod --silent
    success "Pushed Gitea secrets: POSTGRES_* + GITEA__database__* + SECRET_KEY/INTERNAL_TOKEN/JWT_SECRET"
  elif [[ "$TEMPLATE" == "anythingllm-docker" ]]; then
    # AnythingLLM's compose is fail-loud on ANYTHINGLLM_IMAGE, EMBEDDING_ENGINE,
    # OPENROUTER_API_KEY, and JWT_SECRET — a deploy without them refuses to boot.
    # JWT_SECRET is already pushed above; handle the other three here so the
    # automated path produces a bootable instance (previously these were silent
    # gaps that only the manual DEPLOYMENT_GUIDE flow covered).
    log "Pushing AnythingLLM required config..."

    # ANYTHINGLLM_IMAGE — carries the private registry namespace, so it comes
    # from the environment (never a committed default), e.g.
    #   export ANYTHINGLLM_IMAGE=reg.mini.dev/<ns>/anythingllm:<pinned-tag>
    if [[ -n "${ANYTHINGLLM_IMAGE:-}" ]]; then
      if [[ "$ANYTHINGLLM_IMAGE" == *:latest || "$ANYTHINGLLM_IMAGE" != *:* ]]; then
        error "ANYTHINGLLM_IMAGE must be a pinned tag (got: $ANYTHINGLLM_IMAGE) — Minimus rotates :latest"
        exit 1
      fi
      infisical secrets set ANYTHINGLLM_IMAGE="$ANYTHINGLLM_IMAGE" --projectId="$PROJECT_ID" --env=prod --silent
      success "Pushed ANYTHINGLLM_IMAGE"
    elif [[ "$SKIP_IMAGE" == "true" ]]; then
      warn "--skip-image: ANYTHINGLLM_IMAGE not pushed — the container will refuse to boot until you set it in Infisical (pinned tag)"
    else
      error "ANYTHINGLLM_IMAGE is required (the instance cannot boot without it)."
      error "  export ANYTHINGLLM_IMAGE=reg.mini.dev/<ns>/anythingllm:<pinned-tag>  and re-run,"
      error "  or pass --skip-image to explicitly defer (instance stays down until set in Infisical)."
      exit 1
    fi

    # Embedding config — must match whatever built the LanceDB vectors; for a
    # brand-new instance the fleet default is openrouter. Overridable via env.
    infisical secrets set EMBEDDING_ENGINE="${EMBEDDING_ENGINE:-openrouter}" --projectId="$PROJECT_ID" --env=prod --silent
    success "Pushed EMBEDDING_ENGINE (${EMBEDDING_ENGINE:-openrouter})"
    if [[ -n "${EMBEDDING_MODEL_PREF:-}" ]]; then
      infisical secrets set EMBEDDING_MODEL_PREF="$EMBEDDING_MODEL_PREF" --projectId="$PROJECT_ID" --env=prod --silent
      success "Pushed EMBEDDING_MODEL_PREF"
    fi

    # BACKUP_GPG_PUBLIC_KEY — per-customer client-side backup encryption (GPG,
    # ed25519/cv25519, no passphrase — protection at rest is the secret store).
    # The backup script encrypts tarballs with this PUBLIC key before upload,
    # so objects in Spaces are ciphertext to DO. The PRIVATE key goes to
    # operator-tools — it must never live in the site project the droplet's
    # Machine Identity can read, or the box could decrypt its own offsite
    # backups and the key-off-box guarantee is gone. Keys are generated in an
    # ephemeral GNUPGHOME so nothing lands in the operator's real keyring.
    if command -v gpg &>/dev/null; then
      log "Generating per-customer backup encryption keypair (GPG)..."
      GPG_KEYHOME="$(mktemp -d)"
      chmod 700 "$GPG_KEYHOME"
      BACKUP_KEY_UID="backups+${PROJECT_NAME}@weown.invalid"
      cat > "$GPG_KEYHOME/genkey" <<GENKEY
%no-protection
Key-Type: eddsa
Key-Curve: ed25519
Subkey-Type: ecdh
Subkey-Curve: cv25519
Name-Real: ${PROJECT_NAME} backup
Name-Email: ${BACKUP_KEY_UID}
Expire-Date: 0
%commit
GENKEY
      GNUPGHOME="$GPG_KEYHOME" gpg --batch --gen-key "$GPG_KEYHOME/genkey" 2>/dev/null
      GPG_PUB="$(GNUPGHOME="$GPG_KEYHOME" gpg --batch --armor --export "$BACKUP_KEY_UID")"
      GPG_PRIV_SECRET_NAME="BACKUP_GPG_PRIVATE_KEY_${PROJECT_NAME//[^a-zA-Z0-9]/_}"
      infisical secrets set BACKUP_GPG_PUBLIC_KEY="$GPG_PUB" --projectId="$PROJECT_ID" --env=prod --silent
      infisical secrets set "$GPG_PRIV_SECRET_NAME=$(GNUPGHOME="$GPG_KEYHOME" gpg --batch --armor --export-secret-keys "$BACKUP_KEY_UID")" --projectId=operator-tools --env=prod --silent
      rm -rf "$GPG_KEYHOME"
      success "Backup encryption keypair provisioned (public key → site project; private key → operator-tools/$GPG_PRIV_SECRET_NAME)"
    else
      warn "gpg not found (brew install gnupg) — remote backups will be UNENCRYPTED until BACKUP_GPG_PUBLIC_KEY is set in the site project"
    fi

    # OPENROUTER_API_KEY — mint a per-customer, budget-capped key via the
    # provisioning helper (reads OPENROUTER_PROVISIONING_KEY from the
    # operator-tools Infisical project; cap defaults to \$50/mo, override with
    # OPENROUTER_LIMIT_USD). Fail-fast on failure: a warn-and-continue here
    # ships an instance that cannot boot. --skip-llm-key defers explicitly.
    if [[ "$SKIP_LLM_KEY" == "true" ]]; then
      warn "--skip-llm-key: OpenRouter key not minted — the container will not boot until OPENROUTER_API_KEY exists in the project"
    elif bash "$SCRIPT_DIR/provision-openrouter-key.sh" \
         --customer "$SITE_NAME" \
         --project-id "$PROJECT_ID" \
         --limit-usd "${OPENROUTER_LIMIT_USD:-50}"; then
      success "Minted per-customer OpenRouter key (capped \$${OPENROUTER_LIMIT_USD:-50}/mo)"
    else
      error "Could not mint the OpenRouter key (check OPENROUTER_PROVISIONING_KEY in operator-tools)."
      error "  Fix and re-run, mint manually with scripts/provision-openrouter-key.sh,"
      error "  or pass --skip-llm-key to explicitly defer (instance stays down until the key exists)."
      exit 1
    fi
  fi

  # Get shared secrets from operator-tools
  SPACES_ACCESS_KEY=$(infisical secrets get SPACES_ACCESS_KEY --projectId=operator-tools --env=prod --plain 2>/dev/null || echo "")
  SPACES_SECRET_KEY=$(infisical secrets get SPACES_SECRET_KEY --projectId=operator-tools --env=prod --plain 2>/dev/null || echo "")

  if [[ -n "$SPACES_ACCESS_KEY" && -n "$SPACES_SECRET_KEY" ]]; then
    infisical secrets set SPACES_ACCESS_KEY="$SPACES_ACCESS_KEY" --projectId="$PROJECT_ID" --env=prod --silent
    infisical secrets set SPACES_SECRET_KEY="$SPACES_SECRET_KEY" --projectId="$PROJECT_ID" --env=prod --silent
    success "Pushed shared Spaces credentials"
  fi

  # Create site Machine Identity (Tier 2) via API (POST /api/v1/identities)
  log "Creating site Machine Identity (Tier 2)..."
  MI_IDENTITY_ID=$(curl -s -X POST https://app.infisical.com/api/v1/identities \
    -H "Authorization: Bearer $TIER1_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"name\":\"$PROJECT_NAME-mi\",\"role\":\"member\"}" \
    | jq -r '.identity.id // empty')

  if [[ -z "$MI_IDENTITY_ID" ]]; then
    error "Failed to create site Machine Identity"
    exit 1
  fi

  # Attach Universal Auth to the identity and get credentials
  log "Attaching Universal Auth to Machine Identity..."
  MI_AUTH_OUTPUT=$(curl -s -X POST "https://app.infisical.com/api/v1/auth/universal-auth/identities/$MI_IDENTITY_ID" \
    -H "Authorization: Bearer $TIER1_TOKEN" \
    -H "Content-Type: application/json")

  MI_CLIENT_ID=$(echo "$MI_AUTH_OUTPUT" | jq -r '.identityUniversalAuth.clientId // empty')

  # Create a client secret for the identity
  MI_SECRET_OUTPUT=$(curl -s -X POST "https://app.infisical.com/api/v1/auth/universal-auth/identities/$MI_IDENTITY_ID/client-secrets" \
    -H "Authorization: Bearer $TIER1_TOKEN" \
    -H "Content-Type: application/json")

  MI_CLIENT_SECRET=$(echo "$MI_SECRET_OUTPUT" | jq -r '.clientSecret // empty')

  if [[ -z "$MI_CLIENT_ID" || -z "$MI_CLIENT_SECRET" ]]; then
    error "Failed to create Machine Identity credentials"
    exit 1
  fi

  # Add identity to project with member role
  log "Adding Machine Identity to project..."
  curl -s -X POST "https://app.infisical.com/api/v1/projects/$PROJECT_ID/memberships/identities/$MI_IDENTITY_ID" \
    -H "Authorization: Bearer $TIER1_TOKEN" \
    -H "Content-Type: application/json" \
    -d '{"role":"member"}' &>/dev/null

  success "Created site Machine Identity: $MI_CLIENT_ID"

  # Checkpoint: Display credentials
  echo ""
  echo "==================================================================="
  echo "  Infisical Project Created"
  echo "==================================================================="
  echo "  Project ID: $PROJECT_ID"
  echo "  Site MI Client ID: $MI_CLIENT_ID"
  if [[ "$AUTO_MODE" == "true" ]]; then
    echo "  Site MI Client Secret: <redacted in --auto mode>"
  else
    echo "  Site MI Client Secret: $MI_CLIENT_SECRET"
  fi
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

# Reduce risk of Tier 1/2 MI credential leakage via environment / child
# processes (copier/tofu/ansible). Unconditional on purpose: in --skip-infisical
# mode the caller may have exported TIER1_*/INFISICAL_* into our environment, and
# those high-privilege creds must not be inherited by children. (In skip mode the
# INFISICAL_* were already unset above after copying to MI_CLIENT_ID/SECRET;
# re-unsetting is harmless. None of these are referenced after this point.)
unset INFISICAL_CLIENT_ID INFISICAL_CLIENT_SECRET TIER1_CLIENT_ID TIER1_CLIENT_SECRET 2>/dev/null || true

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

  # Write terraform.tfvars (gitignored)
  log "Writing terraform.tfvars..."
  cat > "$SITE_DIR/terraform/terraform.tfvars" <<EOF
# Generated by deploy-new-site.sh — DO NOT COMMIT
infisical_client_id     = "$MI_CLIENT_ID"
infisical_client_secret = "$MI_CLIENT_SECRET"
infisical_project_id    = "$PROJECT_ID"
infisical_environment   = "prod"
EOF
  chmod 600 "$SITE_DIR/terraform/terraform.tfvars"

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

    # Ensure local plan + tfvars are cleaned up on any exit from this point forward.
    TFPLAN_PATH="$SITE_DIR/terraform/tfplan"
    TFVARS_PATH="$SITE_DIR/terraform/terraform.tfvars"
    trap 'rm -f "$TFPLAN_PATH" "$TFVARS_PATH"' EXIT INT TERM

    # Checkpoint: Display plan
    echo ""
    echo "==================================================================="
    echo "  Infrastructure Plan"
    echo "==================================================================="
    tofu show tfplan | head -50
    echo "  ... (truncated; full plan is stored in the local 'tfplan' file)"
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
      if ssh -o StrictHostKeyChecking=accept-new -o ConnectTimeout=5 -o BatchMode=yes "root@$DROPLET_IP" \
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

    # Run smoke test framework
    log "Running smoke test framework..."
    # Export so the framework + hooks inherit the resolved droplet IP and site name
    export DROPLET_IP SITE_NAME
    SMOKE_TEST_HOOKS="$REPO_ROOT/$TEMPLATE/template/scripts/smoke-test-hooks.sh"
    if [ -f "$SMOKE_TEST_HOOKS" ]; then
      if "$REPO_ROOT/scripts/smoke-test-framework.sh" "$SITE_DIR" "$SMOKE_TEST_HOOKS"; then
        success "Smoke test passed"
      else
        warn "Smoke test failed (advisory - deployment succeeded but some checks failed)"
        warn "Review smoke test output above for details"
      fi
    else
      if "$REPO_ROOT/scripts/smoke-test-framework.sh" "$SITE_DIR"; then
        success "Smoke test passed (generic checks only)"
      else
        warn "Smoke test failed (advisory - deployment succeeded but some checks failed)"
        warn "Review smoke test output above for details"
      fi
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

if [[ "$DRY_RUN" == "true" ]]; then
  log "[DRY RUN] Would generate deployment report: $REPORT_FILE"
  exit 0
fi

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
