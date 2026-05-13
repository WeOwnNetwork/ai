#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SITE_KEY="${1:-}"
[[ -z "$SITE_KEY" ]] && { echo "Usage: $0 <site-key>"; exit 1; }

SITE_DIR="$ROOT/sites/$SITE_KEY"
[[ -d "$SITE_DIR" ]] && { echo "Site '$SITE_KEY' already exists"; exit 2; }

mkdir -p "$SITE_DIR/overrides"
cat > "$SITE_DIR/site.config.yaml" <<EOF
site:
  key: "$SITE_KEY"
  name: "{{SITE_NAME}}"
  domain: "{{SITE_DOMAIN}}"
  description: "{{SITE_DESCRIPTION}}"
  palette:
    primary: "{{PRIMARY_COLOR}}"
    secondary: "{{SECONDARY_COLOR}}"
    accent: "{{ACCENT_COLOR}}"
  logo_svg: "./branding/$SITE_KEY-logo.svg"
features:
  landing_route: true
  forms: false
  analytics: true
  social_media: false
EOF

cat > "$SITE_DIR/values-staging.yaml" <<EOF
image:
  repository: "{{IMAGE_REPOSITORY}}"
  tag: "{{IMAGE_TAG}}"
wordpress:
  siteUrl: "{{STAGING_SITE_URL}}"
  title: "{{SITE_TITLE}} - Staging"
  adminEmail: "{{ADMIN_EMAIL}}"
  debug: true
EOF

cat > "$SITE_DIR/values-prod.yaml" <<EOF
image:
  repository: "{{IMAGE_REPOSITORY}}"
  tag: "{{IMAGE_TAG}}"
wordpress:
  siteUrl: "{{SITE_URL}}"
  title: "{{SITE_TITLE}}"
  adminEmail: "{{ADMIN_EMAIL}}"
EOF

echo "Created skeleton for site '$SITE_KEY' at $SITE_DIR"
