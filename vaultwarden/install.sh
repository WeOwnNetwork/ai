#!/bin/bash

# WeOwn Vaultwarden One-Line Installer
# Downloads and runs the interactive deployment script

set -euo pipefail

# Colors
BLUE='\033[0;34m'
GREEN='\033[0;32m'
NC='\033[0m'

echo -e "${BLUE}🔐 WeOwn Vaultwarden Installer${NC}"
echo "Downloading deployment files..."

# Create temporary directory
TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR"

# Clone only the vaultwarden directory
git clone --filter=blob:none --sparse https://github.com/WeOwnNetwork/ai.git
cd ai
git sparse-checkout set vaultwarden
cd vaultwarden

echo -e "${GREEN}✓ Files downloaded successfully${NC}"
echo "Starting interactive deployment..."
echo

# Make script executable and run
chmod +x deploy.sh
./deploy.sh

# Cleanup
echo "Cleaning up temporary files..."
rm -rf "$TEMP_DIR"
