#!/bin/bash
# AnythingLLM MCP Server Management Script
# Version: 1.0.0
# WeOwn Enterprise - Manages MCP server configurations for AnythingLLM deployments
#
# This script allows you to:
# - Add FluentMCP servers (WordPress integration)
# - Add custom MCP servers
# - Modify existing MCP server configurations
# - List all configured MCP servers

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Default namespace
NAMESPACE="anything-llm"

# MCP config file path inside the container
MCP_CONFIG_PATH="/app/server/storage/plugins/anythingllm_mcp_servers.json"
PLUGINS_DIR="/app/server/storage/plugins"

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

print_banner() {
    echo -e "${CYAN}"
    echo "╔═══════════════════════════════════════════════════════════════════╗"
    echo "║        AnythingLLM MCP Server Management - WeOwn Enterprise       ║"
    echo "╚═══════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

print_step() {
    echo -e "${CYAN}→ $1${NC}"
}

# ============================================================================
# CLUSTER AND INSTANCE DETECTION
# ============================================================================

check_prerequisites() {
    print_step "Checking prerequisites..."
    
    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        print_error "kubectl is not installed. Please install kubectl first."
        exit 1
    fi
    
    # Check jq for JSON parsing
    if ! command -v jq &> /dev/null; then
        print_error "jq is not installed. Please install jq first."
        echo "  Install with: brew install jq"
        exit 1
    fi
    
    print_success "All prerequisites met"
}

detect_cluster() {
    print_step "Detecting current Kubernetes cluster..."
    
    # Get current context
    CURRENT_CONTEXT=$(kubectl config current-context 2>/dev/null)
    if [[ -z "$CURRENT_CONTEXT" ]]; then
        print_error "No Kubernetes context found. Please configure kubectl."
        exit 1
    fi
    
    # Extract cluster name from context
    CLUSTER_NAME=$(echo "$CURRENT_CONTEXT" | sed 's/do-nyc1-//' | sed 's/do-sfo1-//' | sed 's/do-.*-//')
    
    # Get cluster info
    CLUSTER_SERVER=$(kubectl config view -o jsonpath="{.clusters[?(@.name=='$CURRENT_CONTEXT')].cluster.server}" 2>/dev/null || echo "Unknown")
    
    echo ""
    echo -e "${CYAN}┌─────────────────────────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}│${NC} Current Cluster Information                                    ${CYAN}│${NC}"
    echo -e "${CYAN}├─────────────────────────────────────────────────────────────────┤${NC}"
    echo -e "${CYAN}│${NC} Context:  ${GREEN}$CURRENT_CONTEXT${NC}"
    echo -e "${CYAN}│${NC} Cluster:  ${GREEN}$CLUSTER_NAME${NC}"
    echo -e "${CYAN}│${NC} Server:   ${GREEN}$CLUSTER_SERVER${NC}"
    echo -e "${CYAN}└─────────────────────────────────────────────────────────────────┘${NC}"
    echo ""
}

check_anythingllm_instance() {
    print_step "Checking for AnythingLLM deployment..."
    
    # Check if namespace exists
    if ! kubectl get namespace "$NAMESPACE" &> /dev/null; then
        print_error "Namespace '$NAMESPACE' does not exist on this cluster."
        print_info "AnythingLLM is not deployed on this cluster."
        exit 1
    fi
    
    # Get deployment status
    DEPLOYMENT_STATUS=$(kubectl get deployment -n "$NAMESPACE" -l app.kubernetes.io/name=anythingllm -o jsonpath='{.items[0].status.conditions[?(@.type=="Available")].status}' 2>/dev/null)
    
    if [[ "$DEPLOYMENT_STATUS" != "True" ]]; then
        print_error "AnythingLLM deployment is not healthy."
        print_info "Deployment status: $DEPLOYMENT_STATUS"
        kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=anythingllm 2>/dev/null
        exit 1
    fi
    
    # Get pod name and status
    POD_NAME=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=anythingllm -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    POD_STATUS=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=anythingllm -o jsonpath='{.items[0].status.phase}' 2>/dev/null)
    POD_READY=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=anythingllm -o jsonpath='{.items[0].status.containerStatuses[0].ready}' 2>/dev/null)
    
    if [[ "$POD_STATUS" != "Running" ]] || [[ "$POD_READY" != "true" ]]; then
        print_error "AnythingLLM pod is not running or not ready."
        print_info "Pod: $POD_NAME | Status: $POD_STATUS | Ready: $POD_READY"
        exit 1
    fi
    
    # Get ingress URL if available
    INGRESS_HOST=$(kubectl get ingress -n "$NAMESPACE" -o jsonpath='{.items[0].spec.rules[0].host}' 2>/dev/null || echo "Not configured")
    
    echo ""
    echo -e "${CYAN}┌─────────────────────────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}│${NC} AnythingLLM Instance Status                                    ${CYAN}│${NC}"
    echo -e "${CYAN}├─────────────────────────────────────────────────────────────────┤${NC}"
    echo -e "${CYAN}│${NC} Pod:      ${GREEN}$POD_NAME${NC}"
    echo -e "${CYAN}│${NC} Status:   ${GREEN}$POD_STATUS${NC}"
    echo -e "${CYAN}│${NC} Ready:    ${GREEN}$POD_READY${NC}"
    echo -e "${CYAN}│${NC} URL:      ${GREEN}https://$INGRESS_HOST${NC}"
    echo -e "${CYAN}└─────────────────────────────────────────────────────────────────┘${NC}"
    echo ""
    
    print_success "AnythingLLM instance is active and healthy"
}

confirm_cluster_selection() {
    echo ""
    echo -e "${YELLOW}═══════════════════════════════════════════════════════════════════${NC}"
    read -p "Is this the cluster and instance you want to configure MCP for? (y/n): " CONFIRM
    echo -e "${YELLOW}═══════════════════════════════════════════════════════════════════${NC}"
    
    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
        print_info "Operation cancelled. Switch to the correct cluster and run again."
        echo ""
        echo "To switch clusters, use:"
        echo "  ../k8s/cluster-switching/switch-cluster.sh <cluster-name>"
        exit 0
    fi
    
    print_success "Cluster confirmed. Proceeding with MCP configuration..."
}

# ============================================================================
# PLUGINS DIRECTORY AND CONFIG FILE MANAGEMENT
# ============================================================================

ensure_plugins_directory() {
    print_step "Verifying plugins directory exists..."
    
    POD_NAME=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=anythingllm -o jsonpath='{.items[0].metadata.name}')
    
    # Check if plugins directory exists
    if kubectl exec -n "$NAMESPACE" "$POD_NAME" -- test -d "$PLUGINS_DIR" 2>/dev/null; then
        print_success "Plugins directory exists: $PLUGINS_DIR"
    else
        print_warning "Plugins directory does not exist. Creating..."
        kubectl exec -n "$NAMESPACE" "$POD_NAME" -- mkdir -p "$PLUGINS_DIR"
        print_success "Created plugins directory: $PLUGINS_DIR"
    fi
}

check_mcp_config_file() {
    print_step "Checking MCP configuration file..."
    
    POD_NAME=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=anythingllm -o jsonpath='{.items[0].metadata.name}')
    
    # Check if config file exists
    if kubectl exec -n "$NAMESPACE" "$POD_NAME" -- test -f "$MCP_CONFIG_PATH" 2>/dev/null; then
        print_success "MCP config file exists: $MCP_CONFIG_PATH"
        
        # Read current config
        CURRENT_CONFIG=$(kubectl exec -n "$NAMESPACE" "$POD_NAME" -- cat "$MCP_CONFIG_PATH" 2>/dev/null)
        
        # Check if file has content
        if [[ -z "$CURRENT_CONFIG" ]] || [[ "$CURRENT_CONFIG" == "{}" ]] || [[ "$CURRENT_CONFIG" == '{"mcpServers":{}}' ]]; then
            CONFIG_EMPTY=true
        else
            CONFIG_EMPTY=false
        fi
    else
        print_warning "MCP config file does not exist. Will be created when adding first server."
        CONFIG_EMPTY=true
        CURRENT_CONFIG='{"mcpServers":{}}'
    fi
}

list_mcp_servers() {
    echo ""
    echo -e "${CYAN}┌─────────────────────────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}│${NC} Current MCP Servers Configuration                               ${CYAN}│${NC}"
    echo -e "${CYAN}└─────────────────────────────────────────────────────────────────┘${NC}"
    
    if [[ "$CONFIG_EMPTY" == true ]]; then
        echo ""
        print_warning "No MCP servers are currently configured."
        echo ""
        return 0
    fi
    
    # Parse and display servers
    echo ""
    SERVER_NAMES=$(echo "$CURRENT_CONFIG" | jq -r '.mcpServers | keys[]' 2>/dev/null)
    
    if [[ -z "$SERVER_NAMES" ]]; then
        print_warning "No MCP servers are currently configured."
        echo ""
        return 0
    fi
    
    SERVER_COUNT=0
    while IFS= read -r SERVER_NAME; do
        ((SERVER_COUNT++))
        COMMAND=$(echo "$CURRENT_CONFIG" | jq -r ".mcpServers[\"$SERVER_NAME\"].command" 2>/dev/null)
        ARGS=$(echo "$CURRENT_CONFIG" | jq -r ".mcpServers[\"$SERVER_NAME\"].args | join(\" \")" 2>/dev/null)
        
        echo -e "  ${GREEN}$SERVER_COUNT. $SERVER_NAME${NC}"
        echo -e "     Command: ${BLUE}$COMMAND $ARGS${NC}"
        
        # Check for env vars
        ENV_KEYS=$(echo "$CURRENT_CONFIG" | jq -r ".mcpServers[\"$SERVER_NAME\"].env | keys[]?" 2>/dev/null)
        if [[ -n "$ENV_KEYS" ]]; then
            echo -e "     Env vars: ${YELLOW}$(echo $ENV_KEYS | tr '\n' ', ' | sed 's/,$//')${NC}"
        fi
        echo ""
    done <<< "$SERVER_NAMES"
    
    print_info "Total servers configured: $SERVER_COUNT"
    echo ""
}

# ============================================================================
# ADD FLUENTMCP SERVER
# ============================================================================

add_fluentmcp_server() {
    echo ""
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║                    Add FluentMCP Server                           ║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    print_info "FluentMCP connects AnythingLLM to WordPress sites via the ML MCP Server."
    print_info "You can add multiple FluentMCP servers for different WordPress sites."
    echo ""
    
    # Get cluster slug
    echo -e "${YELLOW}Enter the cluster/site slug for this FluentMCP server.${NC}"
    echo -e "This will be used in the server name: fmcp-[SLUG]"
    echo -e "Example: weown, romandid, yonks, llmfeed"
    echo ""
    read -p "Cluster/Site slug: " CLUSTER_SLUG
    
    if [[ -z "$CLUSTER_SLUG" ]]; then
        print_error "Cluster slug cannot be empty."
        return 1
    fi
    
    # Sanitize slug (lowercase, alphanumeric and hyphens only)
    CLUSTER_SLUG=$(echo "$CLUSTER_SLUG" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g')
    SERVER_NAME="fmcp-$CLUSTER_SLUG"
    
    # Check if server already exists
    if echo "$CURRENT_CONFIG" | jq -e ".mcpServers[\"$SERVER_NAME\"]" &>/dev/null; then
        print_warning "A server named '$SERVER_NAME' already exists."
        read -p "Do you want to overwrite it? (y/n): " OVERWRITE
        if [[ ! "$OVERWRITE" =~ ^[Yy]$ ]]; then
            print_info "Operation cancelled."
            return 0
        fi
    fi
    
    echo ""
    
    # Get WordPress URL
    echo -e "${YELLOW}Enter the WordPress site URL.${NC}"
    echo -e "Format: https://your-site.com (include https://)"
    echo -e "Example: https://weown.agency"
    echo ""
    read -p "WordPress URL: " WORDPRESS_URL
    
    if [[ -z "$WORDPRESS_URL" ]]; then
        print_error "WordPress URL cannot be empty."
        return 1
    fi
    
    # Validate URL format
    if [[ ! "$WORDPRESS_URL" =~ ^https?:// ]]; then
        print_warning "URL should start with https:// - adding it automatically."
        WORDPRESS_URL="https://$WORDPRESS_URL"
    fi
    
    echo ""
    
    # Get WordPress username
    echo -e "${YELLOW}Enter the WordPress application password username.${NC}"
    echo -e "This is the username for the application password created in WordPress."
    echo -e "Example: AnythingLLM_FluentMCP"
    echo ""
    read -p "WordPress Username: " WORDPRESS_USERNAME
    
    if [[ -z "$WORDPRESS_USERNAME" ]]; then
        print_error "WordPress username cannot be empty."
        return 1
    fi
    
    echo ""
    
    # Get WordPress password
    echo -e "${YELLOW}Enter the WordPress application password.${NC}"
    echo -e "This is the application password generated in WordPress (NOT the user login password)."
    echo -e "Format: xxxx xxxx xxxx xxxx xxxx xxxx (spaces will be removed automatically)"
    echo ""
    read -s -p "WordPress Password: " WORDPRESS_PASSWORD
    echo ""
    
    if [[ -z "$WORDPRESS_PASSWORD" ]]; then
        print_error "WordPress password cannot be empty."
        return 1
    fi
    
    # Remove spaces from password (WordPress app passwords have spaces)
    WORDPRESS_PASSWORD=$(echo "$WORDPRESS_PASSWORD" | tr -d ' ')
    
    echo ""
    print_step "Creating FluentMCP server configuration..."
    
    # Build the new server config
    NEW_SERVER_CONFIG=$(cat <<EOF
{
    "command": "npx",
    "args": ["-y", "@wplaunchify/ml-mcp-server@latest"],
    "env": {
        "WORDPRESS_API_URL": "$WORDPRESS_URL",
        "WORDPRESS_USERNAME": "$WORDPRESS_USERNAME",
        "WORDPRESS_PASSWORD": "$WORDPRESS_PASSWORD"
    }
}
EOF
)
    
    # Add server to config
    UPDATED_CONFIG=$(echo "$CURRENT_CONFIG" | jq --arg name "$SERVER_NAME" --argjson config "$NEW_SERVER_CONFIG" '.mcpServers[$name] = $config')
    
    # Write config to pod
    write_config_to_pod "$UPDATED_CONFIG"
    
    echo ""
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                FluentMCP Server Added Successfully                ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  Server Name:  ${CYAN}$SERVER_NAME${NC}"
    echo -e "  WordPress:    ${CYAN}$WORDPRESS_URL${NC}"
    echo -e "  Username:     ${CYAN}$WORDPRESS_USERNAME${NC}"
    echo ""
    print_info "Go to Agent Skills page in AnythingLLM and click 'Refresh' to load the new server."
}

# ============================================================================
# ADD CUSTOM MCP SERVER
# ============================================================================

add_custom_mcp_server() {
    echo ""
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║                    Add Custom MCP Server                          ║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    print_info "Adding a custom MCP server requires the following information:"
    print_info "  - Server name (unique identifier)"
    print_info "  - Command (e.g., npx, node, python, uvx)"
    print_info "  - Arguments (command arguments)"
    print_info "  - Environment variables (optional)"
    echo ""
    
    # Get server name
    echo -e "${YELLOW}Enter a unique name for this MCP server.${NC}"
    echo -e "Use lowercase letters, numbers, and hyphens only."
    echo -e "Example: my-custom-server, github-mcp, filesystem-server"
    echo ""
    read -p "Server name: " SERVER_NAME
    
    if [[ -z "$SERVER_NAME" ]]; then
        print_error "Server name cannot be empty."
        return 1
    fi
    
    # Sanitize name
    SERVER_NAME=$(echo "$SERVER_NAME" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g')
    
    # Check if server already exists
    if echo "$CURRENT_CONFIG" | jq -e ".mcpServers[\"$SERVER_NAME\"]" &>/dev/null; then
        print_warning "A server named '$SERVER_NAME' already exists."
        read -p "Do you want to overwrite it? (y/n): " OVERWRITE
        if [[ ! "$OVERWRITE" =~ ^[Yy]$ ]]; then
            print_info "Operation cancelled."
            return 0
        fi
    fi
    
    echo ""
    
    # Get command
    echo -e "${YELLOW}Enter the command to run the MCP server.${NC}"
    echo -e "Common commands: npx, node, python, uvx, bash"
    echo ""
    read -p "Command: " MCP_COMMAND
    
    if [[ -z "$MCP_COMMAND" ]]; then
        print_error "Command cannot be empty."
        return 1
    fi
    
    echo ""
    
    # Get arguments
    echo -e "${YELLOW}Enter the command arguments.${NC}"
    echo -e "Enter each argument separated by spaces."
    echo -e "For npx packages, include -y flag first."
    echo -e ""
    echo -e "Examples:"
    echo -e "  For npx:    -y @modelcontextprotocol/server-filesystem /path/to/dir"
    echo -e "  For node:   /path/to/server.js --port 8080"
    echo -e "  For python: -m mcp_server --config config.json"
    echo ""
    read -p "Arguments: " MCP_ARGS_RAW
    
    # Convert space-separated args to JSON array
    MCP_ARGS=$(echo "$MCP_ARGS_RAW" | jq -R 'split(" ") | map(select(. != ""))')
    
    echo ""
    
    # Get environment variables
    echo -e "${YELLOW}Do you need to add environment variables? (y/n)${NC}"
    read -p "Add env vars: " ADD_ENV
    
    ENV_JSON="{}"
    if [[ "$ADD_ENV" =~ ^[Yy]$ ]]; then
        echo ""
        print_info "Enter environment variables one at a time."
        print_info "Type 'done' when finished."
        echo ""
        
        while true; do
            echo -e "${YELLOW}Enter variable name (or 'done' to finish):${NC}"
            read -p "Variable name: " ENV_KEY
            
            if [[ "$ENV_KEY" == "done" ]] || [[ -z "$ENV_KEY" ]]; then
                break
            fi
            
            read -p "Value for $ENV_KEY: " ENV_VALUE
            
            ENV_JSON=$(echo "$ENV_JSON" | jq --arg key "$ENV_KEY" --arg val "$ENV_VALUE" '. + {($key): $val}')
            print_success "Added: $ENV_KEY"
            echo ""
        done
    fi
    
    echo ""
    
    # Ask about autoStart
    echo -e "${YELLOW}Should this server auto-start when Agent Skills page loads? (y/n)${NC}"
    echo -e "If no, you'll need to manually start it from the UI."
    read -p "Auto-start: " AUTO_START
    
    AUTO_START_VALUE="true"
    if [[ ! "$AUTO_START" =~ ^[Yy]$ ]]; then
        AUTO_START_VALUE="false"
    fi
    
    print_step "Creating custom MCP server configuration..."
    
    # Build the new server config
    NEW_SERVER_CONFIG=$(jq -n \
        --arg cmd "$MCP_COMMAND" \
        --argjson args "$MCP_ARGS" \
        --argjson env "$ENV_JSON" \
        --argjson autoStart "$AUTO_START_VALUE" \
        '{
            command: $cmd,
            args: $args,
            env: $env,
            anythingllm: {
                autoStart: $autoStart
            }
        }')
    
    # Remove empty env if no env vars
    if [[ "$ENV_JSON" == "{}" ]]; then
        NEW_SERVER_CONFIG=$(echo "$NEW_SERVER_CONFIG" | jq 'del(.env)')
    fi
    
    # Add server to config
    UPDATED_CONFIG=$(echo "$CURRENT_CONFIG" | jq --arg name "$SERVER_NAME" --argjson config "$NEW_SERVER_CONFIG" '.mcpServers[$name] = $config')
    
    # Write config to pod
    write_config_to_pod "$UPDATED_CONFIG"
    
    echo ""
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║               Custom MCP Server Added Successfully                ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  Server Name:  ${CYAN}$SERVER_NAME${NC}"
    echo -e "  Command:      ${CYAN}$MCP_COMMAND${NC}"
    echo -e "  Arguments:    ${CYAN}$MCP_ARGS_RAW${NC}"
    echo -e "  Auto-start:   ${CYAN}$AUTO_START_VALUE${NC}"
    echo ""
    print_info "Go to Agent Skills page in AnythingLLM and click 'Refresh' to load the new server."
}

# ============================================================================
# MODIFY EXISTING MCP SERVER
# ============================================================================

modify_mcp_server() {
    echo ""
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║                   Modify Existing MCP Server                      ║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    # Get list of servers
    SERVER_NAMES=$(echo "$CURRENT_CONFIG" | jq -r '.mcpServers | keys[]' 2>/dev/null)
    
    if [[ -z "$SERVER_NAMES" ]]; then
        print_warning "No MCP servers are currently configured."
        return 0
    fi
    
    # Display servers with numbers
    echo "Select a server to modify:"
    echo ""
    
    declare -a SERVERS_ARRAY
    SERVER_NUM=0
    while IFS= read -r SERVER_NAME; do
        ((SERVER_NUM++))
        SERVERS_ARRAY[$SERVER_NUM]="$SERVER_NAME"
        echo -e "  ${GREEN}$SERVER_NUM${NC}. $SERVER_NAME"
    done <<< "$SERVER_NAMES"
    
    echo ""
    read -p "Enter server number (or 'cancel'): " SELECTION
    
    if [[ "$SELECTION" == "cancel" ]]; then
        print_info "Operation cancelled."
        return 0
    fi
    
    if ! [[ "$SELECTION" =~ ^[0-9]+$ ]] || [[ "$SELECTION" -lt 1 ]] || [[ "$SELECTION" -gt "$SERVER_NUM" ]]; then
        print_error "Invalid selection."
        return 1
    fi
    
    SELECTED_SERVER="${SERVERS_ARRAY[$SELECTION]}"
    
    echo ""
    echo -e "Selected: ${CYAN}$SELECTED_SERVER${NC}"
    echo ""
    echo "What would you like to do?"
    echo ""
    echo -e "  ${GREEN}1${NC}. Edit server configuration"
    echo -e "  ${GREEN}2${NC}. Delete server"
    echo -e "  ${GREEN}3${NC}. Cancel"
    echo ""
    read -p "Choice: " ACTION
    
    case "$ACTION" in
        1)
            edit_server_config "$SELECTED_SERVER"
            ;;
        2)
            delete_mcp_server "$SELECTED_SERVER"
            ;;
        3|*)
            print_info "Operation cancelled."
            ;;
    esac
}

edit_server_config() {
    local SERVER_NAME="$1"
    
    echo ""
    print_info "Editing: $SERVER_NAME"
    echo ""
    
    # Get current config for this server
    CURRENT_SERVER_CONFIG=$(echo "$CURRENT_CONFIG" | jq ".mcpServers[\"$SERVER_NAME\"]")
    
    echo "Current configuration:"
    echo "$CURRENT_SERVER_CONFIG" | jq '.'
    echo ""
    
    # Check if it's a FluentMCP server
    if [[ "$SERVER_NAME" == fluent-mcp-* ]]; then
        echo -e "${YELLOW}This appears to be a FluentMCP server.${NC}"
        echo "What would you like to update?"
        echo ""
        echo -e "  ${GREEN}1${NC}. WordPress URL"
        echo -e "  ${GREEN}2${NC}. WordPress Username"
        echo -e "  ${GREEN}3${NC}. WordPress Password"
        echo -e "  ${GREEN}4${NC}. All settings"
        echo -e "  ${GREEN}5${NC}. Cancel"
        echo ""
        read -p "Choice: " EDIT_CHOICE
        
        case "$EDIT_CHOICE" in
            1)
                read -p "New WordPress URL: " NEW_URL
                UPDATED_CONFIG=$(echo "$CURRENT_CONFIG" | jq --arg name "$SERVER_NAME" --arg url "$NEW_URL" '.mcpServers[$name].env.WORDPRESS_API_URL = $url')
                write_config_to_pod "$UPDATED_CONFIG"
                print_success "WordPress URL updated."
                ;;
            2)
                read -p "New WordPress Username: " NEW_USER
                UPDATED_CONFIG=$(echo "$CURRENT_CONFIG" | jq --arg name "$SERVER_NAME" --arg user "$NEW_USER" '.mcpServers[$name].env.WORDPRESS_USERNAME = $user')
                write_config_to_pod "$UPDATED_CONFIG"
                print_success "WordPress Username updated."
                ;;
            3)
                read -s -p "New WordPress Password: " NEW_PASS
                echo ""
                NEW_PASS=$(echo "$NEW_PASS" | tr -d ' ')
                UPDATED_CONFIG=$(echo "$CURRENT_CONFIG" | jq --arg name "$SERVER_NAME" --arg pass "$NEW_PASS" '.mcpServers[$name].env.WORDPRESS_PASSWORD = $pass')
                write_config_to_pod "$UPDATED_CONFIG"
                print_success "WordPress Password updated."
                ;;
            4)
                # Delete current server and re-add
                UPDATED_CONFIG=$(echo "$CURRENT_CONFIG" | jq --arg name "$SERVER_NAME" 'del(.mcpServers[$name])')
                CURRENT_CONFIG="$UPDATED_CONFIG"
                add_fluentmcp_server
                ;;
            *)
                print_info "Operation cancelled."
                ;;
        esac
    else
        # Generic server edit
        echo "What would you like to update?"
        echo ""
        echo -e "  ${GREEN}1${NC}. Command"
        echo -e "  ${GREEN}2${NC}. Arguments"
        echo -e "  ${GREEN}3${NC}. Environment variables"
        echo -e "  ${GREEN}4${NC}. Delete and re-create"
        echo -e "  ${GREEN}5${NC}. Cancel"
        echo ""
        read -p "Choice: " EDIT_CHOICE
        
        case "$EDIT_CHOICE" in
            1)
                read -p "New command: " NEW_CMD
                UPDATED_CONFIG=$(echo "$CURRENT_CONFIG" | jq --arg name "$SERVER_NAME" --arg cmd "$NEW_CMD" '.mcpServers[$name].command = $cmd')
                write_config_to_pod "$UPDATED_CONFIG"
                print_success "Command updated."
                ;;
            2)
                read -p "New arguments (space-separated): " NEW_ARGS_RAW
                NEW_ARGS=$(echo "$NEW_ARGS_RAW" | jq -R 'split(" ") | map(select(. != ""))')
                UPDATED_CONFIG=$(echo "$CURRENT_CONFIG" | jq --arg name "$SERVER_NAME" --argjson args "$NEW_ARGS" '.mcpServers[$name].args = $args')
                write_config_to_pod "$UPDATED_CONFIG"
                print_success "Arguments updated."
                ;;
            3)
                print_info "Enter new environment variables. Type 'done' when finished."
                ENV_JSON="{}"
                while true; do
                    read -p "Variable name (or 'done'): " ENV_KEY
                    if [[ "$ENV_KEY" == "done" ]] || [[ -z "$ENV_KEY" ]]; then
                        break
                    fi
                    read -p "Value for $ENV_KEY: " ENV_VALUE
                    ENV_JSON=$(echo "$ENV_JSON" | jq --arg key "$ENV_KEY" --arg val "$ENV_VALUE" '. + {($key): $val}')
                done
                UPDATED_CONFIG=$(echo "$CURRENT_CONFIG" | jq --arg name "$SERVER_NAME" --argjson env "$ENV_JSON" '.mcpServers[$name].env = $env')
                write_config_to_pod "$UPDATED_CONFIG"
                print_success "Environment variables updated."
                ;;
            4)
                UPDATED_CONFIG=$(echo "$CURRENT_CONFIG" | jq --arg name "$SERVER_NAME" 'del(.mcpServers[$name])')
                CURRENT_CONFIG="$UPDATED_CONFIG"
                add_custom_mcp_server
                ;;
            *)
                print_info "Operation cancelled."
                ;;
        esac
    fi
}

delete_mcp_server() {
    local SERVER_NAME="$1"
    
    echo ""
    print_warning "You are about to delete: $SERVER_NAME"
    read -p "Are you sure? (y/n): " CONFIRM
    
    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
        print_info "Operation cancelled."
        return 0
    fi
    
    UPDATED_CONFIG=$(echo "$CURRENT_CONFIG" | jq --arg name "$SERVER_NAME" 'del(.mcpServers[$name])')
    write_config_to_pod "$UPDATED_CONFIG"
    
    print_success "Server '$SERVER_NAME' deleted."
    print_info "Go to Agent Skills page in AnythingLLM and click 'Refresh' to apply changes."
}

# ============================================================================
# WRITE CONFIG TO POD
# ============================================================================

write_config_to_pod() {
    local CONFIG="$1"
    
    POD_NAME=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=anythingllm -o jsonpath='{.items[0].metadata.name}')
    
    # Format JSON nicely
    FORMATTED_CONFIG=$(echo "$CONFIG" | jq '.')
    
    # Write to pod
    echo "$FORMATTED_CONFIG" | kubectl exec -i -n "$NAMESPACE" "$POD_NAME" -- tee "$MCP_CONFIG_PATH" > /dev/null
    
    # Update current config variable
    CURRENT_CONFIG="$FORMATTED_CONFIG"
    
    print_success "Configuration written to pod."
}

# ============================================================================
# MAIN MENU
# ============================================================================

show_main_menu() {
    while true; do
        echo ""
        echo -e "${CYAN}═══════════════════════════════════════════════════════════════════${NC}"
        echo -e "${CYAN}                         MCP Server Options                        ${NC}"
        echo -e "${CYAN}═══════════════════════════════════════════════════════════════════${NC}"
        echo ""
        
        if [[ "$CONFIG_EMPTY" == true ]]; then
            echo -e "  ${GREEN}1${NC}. Add FluentMCP server (WordPress integration)"
            echo -e "  ${GREEN}2${NC}. Add custom MCP server"
            echo -e "  ${GREEN}3${NC}. Refresh configuration"
            echo -e "  ${GREEN}4${NC}. Exit"
        else
            echo -e "  ${GREEN}1${NC}. Add FluentMCP server (WordPress integration)"
            echo -e "  ${GREEN}2${NC}. Add custom MCP server"
            echo -e "  ${GREEN}3${NC}. Modify existing server"
            echo -e "  ${GREEN}4${NC}. List all servers"
            echo -e "  ${GREEN}5${NC}. Refresh configuration"
            echo -e "  ${GREEN}6${NC}. Exit"
        fi
        
        echo ""
        read -p "Select an option: " MENU_CHOICE
        
        if [[ "$CONFIG_EMPTY" == true ]]; then
            case "$MENU_CHOICE" in
                1)
                    add_fluentmcp_server
                    check_mcp_config_file
                    ;;
                2)
                    add_custom_mcp_server
                    check_mcp_config_file
                    ;;
                3)
                    check_mcp_config_file
                    list_mcp_servers
                    ;;
                4)
                    print_info "Goodbye!"
                    exit 0
                    ;;
                *)
                    print_error "Invalid option. Please try again."
                    ;;
            esac
        else
            case "$MENU_CHOICE" in
                1)
                    add_fluentmcp_server
                    check_mcp_config_file
                    ;;
                2)
                    add_custom_mcp_server
                    check_mcp_config_file
                    ;;
                3)
                    modify_mcp_server
                    check_mcp_config_file
                    ;;
                4)
                    list_mcp_servers
                    ;;
                5)
                    check_mcp_config_file
                    list_mcp_servers
                    ;;
                6)
                    print_info "Goodbye!"
                    exit 0
                    ;;
                *)
                    print_error "Invalid option. Please try again."
                    ;;
            esac
        fi
    done
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
    print_banner
    
    # Step 1: Check prerequisites
    check_prerequisites
    
    # Step 2: Detect current cluster
    detect_cluster
    
    # Step 3: Check AnythingLLM instance
    check_anythingllm_instance
    
    # Step 4: Confirm cluster selection
    confirm_cluster_selection
    
    # Step 5: Ensure plugins directory exists
    ensure_plugins_directory
    
    # Step 6: Check MCP config file
    check_mcp_config_file
    
    # Step 7: List current servers
    list_mcp_servers
    
    # Step 8: Show main menu
    show_main_menu
}

# Run main function
main "$@"
