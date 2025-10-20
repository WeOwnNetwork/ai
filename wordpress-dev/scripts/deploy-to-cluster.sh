#!/usr/bin/env bash
#
# WeOwn WordPress Theme - Secure Cluster Deployment Script
#
# Securely deploys the WeOwn Starter theme to a live Kubernetes WordPress instance
# with proper permissions and validation checks.
#
# Usage: ./scripts/deploy-to-cluster.sh <namespace> <pod-name>
# Example: ./scripts/deploy-to-cluster.sh wordpress-romandid wordpress-romandid-d65cd87fb-j495h
#

set -euo pipefail

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
THEME_SRC="$ROOT_DIR/template/wp-content/themes/weown-starter"

# Validate arguments
NAMESPACE="${1:-}"
POD_NAME="${2:-}"

if [[ -z "$NAMESPACE" || -z "$POD_NAME" ]]; then
    echo -e "${RED}Error: Missing required arguments${NC}"
    echo "Usage: $0 <namespace> <pod-name>"
    echo ""
    echo "Example:"
    echo "  $0 wordpress-romandid wordpress-romandid-d65cd87fb-j495h"
    echo ""
    echo "To find your pods:"
    echo "  kubectl get pods --all-namespaces | grep wordpress"
    exit 1
fi

# Validate theme source exists
if [[ ! -d "$THEME_SRC" ]]; then
    echo -e "${RED}Error: Theme source not found at $THEME_SRC${NC}"
    exit 1
fi

echo -e "${GREEN}WeOwn WordPress Theme Deployment${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "Namespace:   ${YELLOW}$NAMESPACE${NC}"
echo -e "Pod:         ${YELLOW}$POD_NAME${NC}"
echo -e "Theme Path:  ${YELLOW}$THEME_SRC${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Step 1: Verify pod exists
echo -e "${YELLOW}[1/5]${NC} Verifying pod exists..."
if ! kubectl get pod "$POD_NAME" -n "$NAMESPACE" &>/dev/null; then
    echo -e "${RED}Error: Pod $POD_NAME not found in namespace $NAMESPACE${NC}"
    echo ""
    echo "Available pods:"
    kubectl get pods -n "$NAMESPACE"
    exit 1
fi
echo -e "${GREEN}✓${NC} Pod verified"

# Step 2: Create temporary archive
echo -e "${YELLOW}[2/5]${NC} Creating temporary theme archive..."
TMP_DIR=$(mktemp -d)
ARCHIVE_NAME="weown-starter-$(date +%s).tar.gz"
ARCHIVE_PATH="$TMP_DIR/$ARCHIVE_NAME"

tar -czf "$ARCHIVE_PATH" -C "$(dirname "$THEME_SRC")" "$(basename "$THEME_SRC")"
echo -e "${GREEN}✓${NC} Archive created: $ARCHIVE_PATH ($(du -h "$ARCHIVE_PATH" | cut -f1))"

# Step 3: Copy theme to pod
echo -e "${YELLOW}[3/5]${NC} Copying theme to pod..."
kubectl cp "$ARCHIVE_PATH" "$NAMESPACE/$POD_NAME:/tmp/$ARCHIVE_NAME"
echo -e "${GREEN}✓${NC} Theme copied to pod"

# Step 4: Extract and set permissions
echo -e "${YELLOW}[4/5]${NC} Extracting theme and setting permissions..."
kubectl exec "$POD_NAME" -n "$NAMESPACE" -- bash -c "
    # Extract theme
    cd /var/www/html/wp-content/themes/
    tar -xzf /tmp/$ARCHIVE_NAME
    
    # Set proper ownership
    chown -R www-data:www-data /var/www/html/wp-content/themes/weown-starter
    
    # Set proper permissions
    find /var/www/html/wp-content/themes/weown-starter -type d -exec chmod 755 {} \;
    find /var/www/html/wp-content/themes/weown-starter -type f -exec chmod 644 {} \;
    
    # Clean up archive
    rm -f /tmp/$ARCHIVE_NAME
    
    # Verify installation
    ls -la /var/www/html/wp-content/themes/weown-starter/
"
echo -e "${GREEN}✓${NC} Theme extracted and permissions set"

# Step 5: Verify installation
echo -e "${YELLOW}[5/5]${NC} Verifying theme installation..."
THEME_FILES=$(kubectl exec "$POD_NAME" -n "$NAMESPACE" -- ls -1 /var/www/html/wp-content/themes/weown-starter/ | wc -l)
echo -e "${GREEN}✓${NC} Theme verified: $THEME_FILES files/directories installed"

# Cleanup
rm -rf "$TMP_DIR"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${GREEN}✓ Deployment Complete!${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Next Steps:"
echo "1. Log into WordPress Admin"
echo "2. Navigate to Appearance > Themes"
echo "3. Activate 'WeOwn Starter' theme"
echo "4. Create a new page and select a template from Page Attributes"
echo ""
echo "Available Templates:"
echo "  • Landing: Cohort/Webinar"
echo "  • Landing: AI Showcase"
echo "  • Landing: Lead Generation"
echo "  • Landing: SaaS Product"
echo "  • Business: About"
echo "  • Business: Services"
echo "  • Business: Contact"
echo "  • Business: Portfolio"
echo ""
