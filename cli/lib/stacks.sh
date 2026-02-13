#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/helm_utils.sh"
source "$(dirname "${BASH_SOURCE[0]}")/do_k8s.sh"

# Define available stacks/apps
# Format: "DisplayName|ReleaseName|Description|ChartPath|Namespace|ValuesFile"
APPS=(
    "Infra: Nginx Ingress|ingress-nginx|Core ingress controller|ingress-nginx/ingress-nginx|infra|"
    "Infra: Cert-Manager|cert-manager|SSL Certificates|jetstack/cert-manager|infra|"
    "Infra: ExternalDNS|external-dns|DO DNS Sync|bitnami/external-dns|infra|"
    "Infra: Monitoring|kube-prometheus-stack|Prometheus & Grafana|prometheus-community/kube-prometheus-stack|infra|"
    "App: WordPress|wordpress|CMS Blog|wordpress/helm|wordpress|wordpress/helm/values.yaml"
    "App: n8n|n8n|Workflow Automation|n8n/helm|n8n|n8n/helm/values.yaml"
    "App: Matomo|matomo|Web Analytics|matomo/helm|matomo|matomo/helm/values.yaml"
    "App: LLM-d|llm-d|LLM Daemon (Beta)|llm-d/helm|llm-d|llm-d/helm/values.yaml"
    "App: Nextcloud|nextcloud|File Storage|nextcloud/helm|nextcloud|nextcloud/helm/values.yaml"
    "App: Vaultwarden|vaultwarden|Password Manager|vaultwarden/helm|vaultwarden|vaultwarden/helm/values.yaml"
)

# Function to parse and install a selection
install_selection() {
    local index=$1
    local entry="${APPS[$index]}"
    
    IFS='|' read -r display_name release_name desc chart ns values <<< "$entry"
    
    # Normalize release name for comparisons (lowercase, trimmed)
    local rn
    rn=$(echo "$release_name" | tr '[:upper:]' '[:lower:]' | xargs)
    
    # Resolve Chart Path (local vs repo)
    local resolved_chart=""
    if [[ "$chart" == *"/"* ]] && [[ -d "$CHART_BASE_DIR/$chart" ]]; then
        resolved_chart="$CHART_BASE_DIR/$chart"
    else
        # Assume repo/chart format
        # Ensure repos are added (basic set)
        helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx >/dev/null 2>&1
        helm repo add jetstack https://charts.jetstack.io >/dev/null 2>&1
        helm repo add bitnami https://charts.bitnami.com/bitnami >/dev/null 2>&1
        helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1
        helm repo update >/dev/null 2>&1
        resolved_chart="$chart"
    fi
    
    # Resolve Values File
    local resolved_values=""
    if [ -n "$values" ] && [ -f "$CHART_BASE_DIR/$values" ]; then
        resolved_values="$CHART_BASE_DIR/$values"
    fi
    
    # Special handling for infra apps (flags passed via cli often, not just values)
    # This is a simplified logic. Real "extensive" logic would have specific functions per app.
    
    # Build extra_args as an array from the start to safely handle values with spaces
    local extra_args_array=()
    
    # E.g., Cert-Manager needs --set installCRDs=true
    if [[ "$rn" == "cert-manager" ]]; then
        extra_args_array+=(--set installCRDs=true)
    fi
    
    # External DNS needs DigitalOcean token stored in a Kubernetes Secret
    if [[ "$rn" == "external-dns" ]]; then
        if [ -z "${DO_TOKEN_SECRET_NAME:-}" ]; then
            log_error "ExternalDNS deployment requires DO_TOKEN_SECRET_NAME to be set to the name of a Kubernetes Secret containing the DigitalOcean API token under the 'digitalocean_api_token' key. Create this Secret securely using an env file (no --from-literal); see the docs for the exact kubectl command."
            return 1
        fi
        extra_args_array+=(--set provider=digitalocean)
        extra_args_array+=(--set digitalocean.secretName="${DO_TOKEN_SECRET_NAME}")
        extra_args_array+=(--set policy=sync)
        extra_args_array+=(--set txtOwnerId="${CLUSTER_NAME:-weown-cluster}")
    fi

    # WordPress: derive domain & email from env if not set in values
    if [[ "$rn" == "wordpress" ]]; then
        local wp_domain="${WP_DOMAIN:-}"
        # Fallback: wordpress.BASE_DOMAIN if WP_DOMAIN not provided
        if [ -z "$wp_domain" ] && [ -n "${BASE_DOMAIN:-}" ]; then
            wp_domain="wordpress.${BASE_DOMAIN}"
        fi
        if [ -z "$wp_domain" ]; then
            log_error "WordPress deployment requires WP_DOMAIN or BASE_DOMAIN in .env to derive the ingress host."
            return 1
        fi
        # Admin password for WordPress (required so secret has 'wordpress-password' key)
        local wp_admin_password="${WP_ADMIN_PASSWORD:-}"
        if [ -z "$wp_admin_password" ]; then
            log_error "WP_ADMIN_PASSWORD must be set in cli/.env (use a strong alphanumeric string) for WordPress admin."
            return 1
        fi
        # Populate chart values overriding placeholders / empty hosts
        extra_args_array+=(--set "wordpress.domain=${wp_domain}")
        extra_args_array+=(--set "wordpress.wordpressPassword=${wp_admin_password}")
        extra_args_array+=(--set "ingress.hosts[0].host=${wp_domain}")
        extra_args_array+=(--set "ingress.tls[0].hosts[0]=${wp_domain}")
        
        # Optionally wire email into WordPress config
        if [ -n "${LETSENCRYPT_EMAIL:-}" ]; then
            extra_args_array+=(--set "wordpress.wordpressEmail=${LETSENCRYPT_EMAIL}")
        fi
    fi

    # n8n: derive domain from env to replace DOMAIN_PLACEHOLDER
    if [[ "$rn" == "n8n" ]]; then
        local n8n_domain="${N8N_DOMAIN:-}"
        if [ -z "$n8n_domain" ] && [ -n "${BASE_DOMAIN:-}" ]; then
            n8n_domain="n8n.${BASE_DOMAIN}"
        fi
        if [ -z "$n8n_domain" ]; then
            log_error "n8n deployment requires N8N_DOMAIN or BASE_DOMAIN in .env to derive the ingress host."
            return 1
        fi
        extra_args_array+=(--set "global.domain=${n8n_domain}")
        if [ -n "${LETSENCRYPT_EMAIL:-}" ]; then
            extra_args_array+=(--set "global.email=${LETSENCRYPT_EMAIL}")
        fi
        extra_args_array+=(--set "n8n.config.N8N_HOST=${n8n_domain}")
        extra_args_array+=(--set "n8n.config.WEBHOOK_URL=https://${n8n_domain}/")
        extra_args_array+=(--set "ingress.hosts[0].host=${n8n_domain}")
        extra_args_array+=(--set "ingress.tls[0].hosts[0]=${n8n_domain}")
        extra_args_array+=(--set "networkPolicy.ingress[0].from[0].namespaceSelector.matchLabels.name=infra")
    fi

    # Nextcloud: derive domain from env to replace DOMAIN_PLACEHOLDER
    if [[ "$rn" == "nextcloud" ]]; then
        local nextcloud_domain="${NEXTCLOUD_DOMAIN:-}"
        if [ -z "$nextcloud_domain" ] && [ -n "${BASE_DOMAIN:-}" ]; then
            nextcloud_domain="nextcloud.${BASE_DOMAIN}"
        fi
        if [ -z "$nextcloud_domain" ]; then
            log_error "Nextcloud deployment requires NEXTCLOUD_DOMAIN or BASE_DOMAIN in .env to derive the ingress host."
            return 1
        fi
        extra_args_array+=(--set "global.domain=${nextcloud_domain}")
        if [ -n "${LETSENCRYPT_EMAIL:-}" ]; then
            extra_args_array+=(--set "global.email=${LETSENCRYPT_EMAIL}")
        fi
        extra_args_array+=(--set "nextcloud.config.NEXTCLOUD_HOST=${nextcloud_domain}")
        extra_args_array+=(--set "nextcloud.config.NEXTCLOUD_TRUSTED_DOMAINS=${nextcloud_domain}")
        extra_args_array+=(--set "ingress.hosts[0].host=${nextcloud_domain}")
        extra_args_array+=(--set "ingress.tls[0].hosts[0]=${nextcloud_domain}")
        extra_args_array+=(--set "networkPolicy.ingress[0].from[0].namespaceSelector.matchLabels.name=infra")
    fi

    # Matomo: derive domain & tracking host from env to replace DOMAIN_PLACEHOLDER
    if [[ "$rn" == "matomo" ]]; then
        local matomo_domain="${MATOMO_DOMAIN:-}"
        if [ -z "$matomo_domain" ] && [ -n "${BASE_DOMAIN:-}" ]; then
            matomo_domain="matomo.${BASE_DOMAIN}"
        fi
        if [ -z "$matomo_domain" ]; then
            log_error "Matomo deployment requires MATOMO_DOMAIN or BASE_DOMAIN in .env to derive the ingress host."
            return 1
        fi
        # WordPress tracking site host for Matomo (defaults to WordPress domain)
        local wp_tracking_host="${WP_DOMAIN:-}"
        if [ -z "$wp_tracking_host" ] && [ -n "${BASE_DOMAIN:-}" ]; then
            wp_tracking_host="wordpress.${BASE_DOMAIN}"
        fi
        # Database auth for MariaDB used by Matomo
        local matomo_db_root_password="${MATOMO_DB_ROOT_PASSWORD:-}"
        local matomo_db_password="${MATOMO_DB_PASSWORD:-$matomo_db_root_password}"
        if [ -z "$matomo_db_root_password" ]; then
            log_error "MATOMO_DB_ROOT_PASSWORD must be set in cli/.env (use a strong alphanumeric string) for Matomo MariaDB."
            return 1
        fi
        # Override ingress + global + website host and DB auth values
        extra_args_array+=(--set "global.domain=${matomo_domain}")
        if [ -n "${LETSENCRYPT_EMAIL:-}" ]; then
            extra_args_array+=(--set "global.email=${LETSENCRYPT_EMAIL}")
            extra_args_array+=(--set "matomo.admin.email=${LETSENCRYPT_EMAIL}")
        fi
        extra_args_array+=(--set "mariadb.auth.rootPassword=${matomo_db_root_password}")
        extra_args_array+=(--set "mariadb.auth.password=${matomo_db_password}")
        extra_args_array+=(--set "ingress.hosts[0].host=${matomo_domain}")
        extra_args_array+=(--set "ingress.tls[0].hosts[0]=${matomo_domain}")
        extra_args_array+=(--set "networkPolicy.ingress[0].from[0].namespaceSelector.matchLabels.name=infra")
        if [ -n "$wp_tracking_host" ]; then
            extra_args_array+=(--set "matomo.website.host=${wp_tracking_host}")
        fi
    fi

    # Vaultwarden: derive domain from env and align NetworkPolicy ingress
    if [[ "$rn" == "vaultwarden" ]]; then
        local vaultwarden_domain="${VAULTWARDEN_DOMAIN:-}"
        local vaultwarden_subdomain="${VAULTWARDEN_SUBDOMAIN:-vault}"
        if [ -z "$vaultwarden_domain" ] && [ -n "${BASE_DOMAIN:-}" ]; then
            vaultwarden_domain="${BASE_DOMAIN}"
        fi
        if [ -z "$vaultwarden_domain" ]; then
            log_error "Vaultwarden deployment requires VAULTWARDEN_DOMAIN or BASE_DOMAIN in .env to derive the domain."
            return 1
        fi
        extra_args_array+=(--set "global.domain=${vaultwarden_domain}")
        extra_args_array+=(--set "global.subdomain=${vaultwarden_subdomain}")
        if [ -n "${LETSENCRYPT_EMAIL:-}" ]; then
            extra_args_array+=(--set "certManager.email=${LETSENCRYPT_EMAIL}")
        fi
        extra_args_array+=(--set "vaultwarden.domain=https://${vaultwarden_subdomain}.${vaultwarden_domain}")
        extra_args_array+=(--set "security.networkPolicy.ingress[0].from[0].namespaceSelector.matchLabels.name=infra")
    fi
    
    log_info "Processing $display_name ($release_name)..."
    if [ ${#extra_args_array[@]} -gt 0 ]; then
        log_info "Helm extra args count: ${#extra_args_array[@]}"
    else
        log_info "Helm extra args: <none>"
    fi
    
    # Call helm deploy
    # Build Helm command as an array to avoid eval/command injection
    local cmd=(helm upgrade --install "$release_name" "$resolved_chart" --namespace "$ns" --create-namespace)
    if [ -n "$resolved_values" ]; then
        cmd+=(-f "$resolved_values")
    fi
    if [ ${#extra_args_array[@]} -gt 0 ]; then
        cmd+=("${extra_args_array[@]}")
    fi
    
    # Avoid logging the full command to prevent leaking secrets in extra_args
    log_info "Executing Helm upgrade for release '$release_name' in namespace '$ns'."
    if "${cmd[@]}"; then
        log_success "$display_name Installed."

        # Post-deploy status logs
        log_info "Helm status for $release_name (namespace: $ns):"
        helm status "$release_name" -n "$ns" || log_warn "helm status failed for $release_name in $ns"

        echo
        log_info "Kubernetes resources in namespace '$ns' after deploying $release_name:"
        kubectl get pods,svc,ingress -n "$ns" || log_warn "kubectl get pods/svc/ingress failed for namespace $ns"

        # Optional: DigitalOcean cluster status (if doctl & CLUSTER_NAME are available)
        if command -v doctl >/dev/null 2>&1 && [ -n "${CLUSTER_NAME:-}" ]; then
            echo
            log_info "DigitalOcean cluster status for $CLUSTER_NAME:"
            doctl kubernetes cluster get "$CLUSTER_NAME" \
              --format Name,Status,Region,Version,NodePools --no-header \
              || log_warn "doctl cluster get failed for $CLUSTER_NAME"
        fi
    else
        log_error "$display_name Installation Failed."
    fi
}
