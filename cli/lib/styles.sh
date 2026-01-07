#!/bin/bash

# ANSI Color Codes
export BLACK='\033[0;30m'
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[0;33m'
export BLUE='\033[0;34m'
export PURPLE='\033[0;35m'
export CYAN='\033[0;36m'
export WHITE='\033[0;37m'
export BOLD='\033[1m'
export NC='\033[0m' # No Color

# Banner Function
show_banner() {
    clear
    echo -e "${CYAN}${BOLD}"
    cat << "EOF"
  _       __        ____                 
 | |     / /__     / __ \_      ______  
 | | /| / / _ \   / / / / | /| / / __ \ 
 | |/ |/ /  __/  / /_/ /| |/ |/ / / / / 
 |__/|__/\___/   \____/ |__/|__/_/ /_/  
                                        
      DigitalOcean K8s Deployer         
EOF
    echo -e "${NC}"
    echo -e "${PURPLE}:: Extensive CLI for custom deployment of WeOwn AI Infrastructure ::${NC}"
    echo -e "${BLUE}:: Managing Clusters, Droplets & Helm Stacks for weown ai ecosystem ::${NC}"
    echo
}

show_cli_help() {
    echo -e "${BOLD}WeOwn CLI navigation:${NC}"
    echo "  1) Manage Kubernetes Cluster (Droplets)"
    echo "     - List, scale, create or delete node pools on your DOKS cluster"
    echo "     - Delete the entire Kubernetes cluster (with confirmation prompts)"
    echo "  2) Deploy Solutions (Stacks)"
    echo "     - Deploy infra (Ingress, cert-manager, ExternalDNS, monitoring)"
    echo "     - Deploy apps (WordPress, Matomo, n8n, AnythingLLM, etc.) into namespaces"
    echo "     - Uses settings from cli/.env (DO_TOKEN, CLUSTER_NAME, BASE_DOMAIN, *DOMAIN, passwords)"
    echo "  3) Deploy Apps on Droplets"
    echo "     - Deploy WordPress (and later other apps) directly on DigitalOcean Droplets"
    echo "     - Uses doctl and DigitalOcean DNS to create droplets and A records"
    echo "  4) List Deployments"
    echo "     - Show Helm releases and namespaces on the current cluster"
    echo "  5) Check Infrastructure Status"
    echo "     - Verify doctl/kubectl connectivity, nodes, and pods across namespaces"
    echo
}

# Helper logging
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Interactive Menu Helper
# Usage: checkbox_menu "Prompt" "Option1" "Option2" ...
# Returns: Selected indices in SELECTED_INDICES array
checkbox_menu() {
	local prompt="$1"
	shift
	local options=("$@")
	local count=${#options[@]}

	clear
	show_banner
	echo -e "${BOLD}$prompt${NC}"
	echo

	# Print numbered options
	local i
	for ((i=0; i<count; i++)); do
		printf "  %d) %s\n" $((i+1)) "${options[i]}"
	done

	echo
	echo "Enter numbers separated by spaces (e.g. 1 3 5), or leave empty to cancel."
	read -rp "Selection: " selection_line

	SELECTED_INDICES=()
	for token in $selection_line; do
		if [[ $token =~ ^[0-9]+$ ]]; then
			local idx=$((token-1))
			if (( idx >= 0 && idx < count )); then
				SELECTED_INDICES+=("$idx")
			fi
		fi
	done
}
