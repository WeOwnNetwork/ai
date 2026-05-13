#!/usr/bin/env bash
# Rotate DO Spaces credentials and update Infisical
# Usage: ./rotate-do-spaces-keys.sh <old-access-key>
#
# This script guides you through rotating DO Spaces credentials.
# It does NOT make API calls — manual steps are required in the DO console.
#
# Compliance: NIST PR.DS, CIS 3.11, ISO A.8.24, SOC 2 CC6.2
set -euo pipefail

OLD_KEY="${1:-}"
if [[ -z "$OLD_KEY" ]]; then
  echo "Usage: $0 <old-access-key-id>"
  echo "Example: $0 <YOUR_ACCESS_KEY_ID>"
  exit 1
fi

echo "==================================================================="
echo "  DO Spaces Credential Rotation Guide"
echo "==================================================================="
echo ""
echo "Old key ID: ${OLD_KEY}"
echo ""
echo "STEP 1: Rotate in DigitalOcean Console"
echo "  → https://cloud.digitalocean.com/account/api/spaces"
echo "  → Delete old key: $OLD_KEY"
echo "  → Generate new key pair"
echo ""
echo "STEP 2: Update Infisical Secrets"
echo "  → Open https://app.infisical.com"
echo "  → Navigate to your keycloak project"
echo "  → Update these secrets:"
echo "       SPACES_ACCESS_KEY = <new-access-key>"
echo "       SPACES_SECRET_KEY = <new-secret-key>"
echo ""
echo "STEP 3: Verify Backup Scripts"
echo "  → The backup script fetches these from Infisical at runtime"
echo "  → No file changes needed if using infisical run wrapper"
echo ""
echo "STEP 4: Document Rotation"
echo "  → Add entry to .github/INCIDENT_RESPONSE.md"
echo "  → Include: date, reason, old key fingerprint (last 4 chars)"
echo ""
echo "STEP 5: Test"
echo "  → Run a manual backup to verify new keys work:"
echo "    ssh root@<droplet> 'cd /opt/sso && infisical run --projectId=xxx --env=prod -- ./backup.sh'"
echo ""
echo "==================================================================="
