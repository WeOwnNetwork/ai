#!/bin/bash

# Helpers for deploying applications directly on DigitalOcean Droplets
# (non-Kubernetes), using doctl and DigitalOcean DNS.

source "$(dirname "${BASH_SOURCE[0]}")/styles.sh"
source "$(dirname "${BASH_SOURCE[0]}")/do_k8s.sh"

# Deploy a WordPress One-Click Droplet and wire a domain to it.
# This is intentionally interactive so it can be used from the legacy CLI.

deploy_wordpress_droplet_interactive() {
	check_doctl

	local default_region=${DO_REGION:-nyc3}
	local default_size="s-1vcpu-1gb"

	log_info "Deploying WordPress on a DigitalOcean Droplet (non-Kubernetes)."

	read -rp "Droplet name [wp-${BASE_DOMAIN:-site}]: " droplet_name
	if [ -z "$droplet_name" ]; then
		droplet_name="wp-${BASE_DOMAIN:-site}"
	fi

	read -rp "Region slug [${default_region}]: " region
	if [ -z "$region" ]; then
		region="$default_region"
	fi

	read -rp "Size slug [${default_size}]: " size
	if [ -z "$size" ]; then
		size="$default_size"
	fi

	read -rp "Domain to map to this droplet (e.g. example.com): " domain
	if [ -z "$domain" ]; then
		log_error "Domain is required. Aborting."
		return 1
	fi

	log_info "Discovering WordPress image slug from DigitalOcean public images..."
	local wp_slug
	wp_slug=$(doctl compute image list --public --format Slug --no-header | grep '^wordpress-' | head -n 1)
	if [ -z "$wp_slug" ]; then
		log_error "Could not find a WordPress image slug via doctl. Please check doctl compute image list."
		return 1
	fi
	log_info "Using WordPress image slug: $wp_slug"

	log_info "Creating droplet '$droplet_name' in region '$region' with size '$size'..."
	if ! doctl compute droplet create "$droplet_name" \
		--region "$region" \
		--image "$wp_slug" \
		--size "$size" \
		--tag-name "wordpress" \
		--enable-monitoring \
		--wait; then
		log_error "Droplet creation failed. Check doctl output above."
		return 1
	fi

	local ip
	ip=$(doctl compute droplet list "$droplet_name" --format PublicIPv4 --no-header | tr -d ' ')
	if [ -z "$ip" ]; then
		log_error "Could not determine droplet IP address."
		return 1
	fi
	log_success "Droplet '$droplet_name' created with IP $ip."

	log_info "Ensuring domain '$domain' exists in DigitalOcean DNS..."
	if ! doctl compute domain get "$domain" >/dev/null 2>&1; then
		if doctl compute domain create "$domain"; then
			log_success "Created DNS zone for $domain."
		else
			log_warn "Failed to create DNS zone for $domain. It may already exist or be managed elsewhere."
		fi
	fi

	log_info "Creating A records (@ and www) pointing to $ip..."
	if ! doctl compute domain records create "$domain" \
		--record-type A \
		--record-name @ \
		--record-data "$ip" \
		--record-ttl 600; then
		log_warn "Failed to create root A record for $domain. It may already exist."
	fi

	if ! doctl compute domain records create "$domain" \
		--record-type A \
		--record-name www \
		--record-data "$ip" \
		--record-ttl 600; then
		log_warn "Failed to create www A record for $domain. It may already exist."
	fi

	log_success "WordPress droplet deployment completed."
	echo
	echo "You can now visit: http://$domain (or http://$ip) to finish WordPress setup."
	echo "Next steps:"
	echo "  - SSH into the droplet: ssh root@$ip"
	echo "  - Complete the WordPress installation wizard."
	echo "  - Optionally run Certbot on the droplet to enable HTTPS for $domain."
}

# Simple sub-menu for droplet-based app deployments

droplet_apps_menu() {
	while true; do
		echo
		log_info "Droplet-based Application Deployment"
		echo "  1) Deploy WordPress on a new Droplet"
		echo "  2) Back to main menu"
		read -rp "Choice: " choice
		case "$choice" in
			1)
				deploy_wordpress_droplet_interactive
				;;
			2)
				return 0
				;;
			*)
				log_warn "Invalid option."
				;;
		esac
	done
}
