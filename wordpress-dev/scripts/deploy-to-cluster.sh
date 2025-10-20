#!/usr/bin/env bash
#
# WeOwn WordPress Theme - Interactive Cluster Deployment Script
#
# Automatically discovers WordPress pods and provides interactive selection.
# No arguments needed - just run the script!
#
# Usage: ./scripts/deploy-to-cluster.sh
#

set -euo pipefail

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
THEME_SRC="$ROOT_DIR/template/wp-content/themes/weown-starter"

# Validate theme source exists
if [[ ! -d "$THEME_SRC" ]]; then
    echo -e "${RED}Error: Theme source not found at $THEME_SRC${NC}"
    exit 1
fi

echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║${NC}  ${GREEN}WeOwn WordPress Theme - Interactive Deployment${NC}      ${CYAN}║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Discover WordPress pods
echo -e "${BLUE}[Discovery]${NC} Scanning cluster for WordPress pods..."
echo ""

# Get all pods with wordpress in the name, running status only
PODS=()
while IFS= read -r line; do
    [[ -n "$line" ]] && PODS+=("$line")
done < <(kubectl get pods --all-namespaces -o json 2>/dev/null | \
    jq -r '.items[] | 
    select(.metadata.name | test("wordpress")) | 
    select(.status.phase == "Running") | 
    select(.metadata.name | test("mariadb|mysql|cron") | not) |
    "\(.metadata.namespace)|\(.metadata.name)|\(.status.phase)"' 2>/dev/null || true)

if [[ ${#PODS[@]} -eq 0 ]]; then
    echo -e "${RED}✗ No running WordPress pods found in cluster${NC}"
    echo ""
    echo "Available namespaces:"
    kubectl get namespaces -o custom-columns=NAME:.metadata.name --no-headers | sed 's/^/  - /'
    echo ""
    echo "Tip: Make sure WordPress is deployed and running"
    exit 1
fi

echo -e "${GREEN}✓ Found ${#PODS[@]} WordPress pod(s)${NC}"
echo ""

# Display selection menu
echo -e "${YELLOW}Select a WordPress pod to deploy to:${NC}"
echo ""

for i in "${!PODS[@]}"; do
    IFS='|' read -r namespace pod_name status <<< "${PODS[$i]}"
    printf "${CYAN}%2d)${NC} ${GREEN}%-25s${NC} ${YELLOW}%-50s${NC} [%s]\n" \
        "$((i+1))" "$namespace" "$pod_name" "$status"
done

echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Get user selection
while true; do
    read -p "$(echo -e ${YELLOW}Enter selection [1-${#PODS[@]}] or 'q' to quit:${NC} )" selection
    
    if [[ "$selection" == "q" ]] || [[ "$selection" == "Q" ]]; then
        echo -e "${YELLOW}Deployment cancelled${NC}"
        exit 0
    fi
    
    if [[ "$selection" =~ ^[0-9]+$ ]] && [[ "$selection" -ge 1 ]] && [[ "$selection" -le ${#PODS[@]} ]]; then
        break
    fi
    
    echo -e "${RED}Invalid selection. Please enter a number between 1 and ${#PODS[@]}${NC}"
done

# Parse selected pod
SELECTED_INDEX=$((selection - 1))
IFS='|' read -r NAMESPACE POD_NAME STATUS <<< "${PODS[$SELECTED_INDEX]}"

echo ""
echo -e "${GREEN}Selected:${NC}"
echo -e "  Namespace: ${YELLOW}$NAMESPACE${NC}"
echo -e "  Pod:       ${YELLOW}$POD_NAME${NC}"
echo ""

# Confirmation
read -p "$(echo -e ${YELLOW}Proceed with deployment? [Y/n]:${NC} )" confirm
if [[ "$confirm" != "Y" ]] && [[ "$confirm" != "y" ]] && [[ -n "$confirm" ]]; then
    echo -e "${YELLOW}Deployment cancelled${NC}"
    exit 0
fi

echo ""
echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║${NC}  ${GREEN}Starting Deployment${NC}                                   ${CYAN}║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Step 1: Verify pod exists
echo -e "${YELLOW}[1/5]${NC} Verifying pod exists..."
if ! kubectl get pod "$POD_NAME" -n "$NAMESPACE" &>/dev/null; then
    echo -e "${RED}Error: Pod $POD_NAME not found in namespace $NAMESPACE${NC}"
    echo ""
    echo "Available pods in namespace $NAMESPACE:"
    kubectl get pods -n "$NAMESPACE" 2>/dev/null || echo "  (namespace may not exist or you don't have access)"
    echo ""
    echo "All WordPress pods across namespaces:"
    kubectl get pods --all-namespaces | grep wordpress || echo "  (no wordpress pods found)"
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
