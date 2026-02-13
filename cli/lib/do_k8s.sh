#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/styles.sh"

# Config: load env for CLI
# Prefer cli/.env, fall back to project-root .env
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if [ -f "$BASE_DIR/cli/.env" ]; then
	ENV_FILE="$BASE_DIR/cli/.env"
elif [ -f "$BASE_DIR/.env" ]; then
	ENV_FILE="$BASE_DIR/.env"
else
	ENV_FILE=""
fi

if [ -n "$ENV_FILE" ]; then
	# Safely load environment variables from the .env file without executing it as shell.
	# Only accept simple KEY=VALUE lines, ignore comments and malformed entries.
	while IFS= read -r line || [ -n "$line" ]; do
		# Trim leading and trailing whitespace using parameter expansion
		# ${var##*[![:space:]]} finds the last non-whitespace char, then % removes trailing whitespace
		# ${var%%[![:space:]]*} finds the first non-whitespace char, then # removes leading whitespace
		line="${line#"${line%%[![:space:]]*}"}"
		line="${line%"${line##*[![:space:]]}"}"

		# Skip empty lines and comments
		if [ -z "$line" ] || [ "${line#\#}" != "$line" ]; then
			continue
		fi

		# Require KEY=VALUE form with a safe variable name
		case "$line" in
			[A-Za-z_][A-Za-z0-9_]*=*)
				key=${line%%=*}
				value=${line#*=}

				# Strip matching surrounding quotes (both double or both single)
				# Only strip if quote appears at both start AND end
				case "$value" in
					\"*\")
						value="${value#\"}"
						value="${value%\"}"
						;;
					\'*\')
						value="${value#\'}"
						value="${value%\'}"
						;;
				esac

				export "$key=$value"
				;;
			*)
				# Ignore lines that are not simple KEY=VALUE assignments
				;;
		esac
	done < "$ENV_FILE"
fi

check_doctl() {
    if ! command -v doctl &> /dev/null; then
        log_error "doctl is not installed."
        exit 1
    fi
    
    # Basic auth check
    if ! doctl account get >/dev/null 2>&1; then
        log_warn "doctl not authenticated. Trying to use DO_TOKEN..."
        if [ -n "$DO_TOKEN" ]; then
            if ! doctl auth init -t "$DO_TOKEN" >/dev/null 2>&1; then
                log_error "Failed to authenticate doctl with DO_TOKEN."
                exit 1
            fi
        else
            log_error "DO_TOKEN not set in .env and doctl not logged in."
            exit 1
        fi
    fi
}

ensure_cluster() {
    local cluster_name=${1:-${CLUSTER_NAME:-weown-cluster}}
    local region=${2:-${DO_REGION:-nyc3}}
    local version=${K8S_VERSION:-"1.33.1-do.0"}
    
    log_info "Checking for cluster: $cluster_name..."
    
    if doctl kubernetes cluster get "$cluster_name" >/dev/null 2>&1; then
        log_success "Cluster '$cluster_name' exists."
    else
        log_info "Creating cluster '$cluster_name'..."
        # Default pool: web-pool
        doctl kubernetes cluster create "$cluster_name" \
            --region "$region" \
            --version "$version" \
            --node-pool "name=web-pool;size=s-2vcpu-4gb;count=2" \
            --wait
        log_success "Cluster created."
    fi
    
    log_info "Configuring kubectl context..."
    doctl kubernetes cluster kubeconfig save "$cluster_name"
}

list_node_pools() {
    local cluster_name=${1:-${CLUSTER_NAME:-weown-cluster}}
    doctl kubernetes cluster node-pool list "$cluster_name"
}

scale_node_pool() {
    local cluster_name=${1:-${CLUSTER_NAME:-weown-cluster}}
    local pool_name=$2
    local count=$3
    
    if [ -z "$pool_name" ] || [ -z "$count" ]; then
        log_error "Usage: scale_node_pool <pool_name> <count>"
        return 1
    fi
    
    log_info "Scaling node pool '$pool_name' to $count nodes..."
    doctl kubernetes cluster node-pool update "$cluster_name" "$pool_name" --count "$count"
    log_success "Scaling initiated."
}

create_node_pool() {
    local cluster_name=${1:-${CLUSTER_NAME:-weown-cluster}}
    local pool_name=$2
    local size=$3
    local count=$4
    local tags=$5 # Optional setup as "role=value"
    
    if [ -z "$pool_name" ] || [ -z "$size" ] || [ -z "$count" ]; then
        log_error "Usage: create_node_pool <pool_name> <size> <count> [label]"
        return 1
    fi
    
    log_info "Creating node pool '$pool_name'..."
    local args=(
        "kubernetes" "cluster" "node-pool" "create" "$cluster_name"
        "--name" "$pool_name"
        "--size" "$size"
        "--count" "$count"
    )
    if [ -n "$tags" ]; then
        args+=("--label" "$tags")
    fi
    doctl "${args[@]}"
}

delete_node_pool() {
    local cluster_name=${1:-${CLUSTER_NAME:-weown-cluster}}
    local pool_name=$2
    
    if [ -z "$pool_name" ]; then
        log_error "Usage: delete_node_pool <pool_name|pool_id>"
        return 1
    fi

    log_warn "Deleting node pool '$pool_name' from cluster '$cluster_name' (this removes all its nodes)..."
    doctl kubernetes cluster node-pool delete "$cluster_name" "$pool_name" --force
}

delete_cluster() {
    local cluster_name=${1:-${CLUSTER_NAME:-weown-cluster}}
    log_warn "You are about to DELETE the Kubernetes cluster '$cluster_name'. This will stop all workloads and remove the control plane."
    read -p "Type the cluster name ('$cluster_name') to confirm, or anything else to cancel: " confirm
    if [ "$confirm" != "$cluster_name" ]; then
        log_info "Cluster deletion cancelled."
        return 0
    fi

    log_warn "Deleting cluster '$cluster_name' via doctl..."
    doctl kubernetes cluster delete "$cluster_name" --force
}
