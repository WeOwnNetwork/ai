#!/usr/bin/env bash
set -euo pipefail

# This script is intended to be run ON THE DROPLET, from inside
# the payless-tax/with-persona directory (or anywhere under it).
# It will:
#   - Install Docker, docker-compose (v1), and Nginx
#   - Start the Docker Compose stack (MySQL + app) via systemd
#   - Configure Nginx to proxy withpersona.payless.tax -> 127.0.0.1:8501
#
# Usage (from your laptop):
#   scp -r . root@<DROPLET_IP>:/opt/weown_corporation/ai/payless-tax/with-persona
#   ssh root@<DROPLET_IP> "cd /opt/weown_corporation/ai/payless-tax/with-persona && \
#       APP_DOMAIN=withpersona.payless.tax bash deploy/setup-withpersona-droplet.sh"
#
# You will be prompted for the root password by ssh; the script itself
# does not handle credentials.

APP_DOMAIN="${APP_DOMAIN:-withpersona.payless.tax}"

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  echo "[ERROR] Please run this script as root on the droplet (e.g. via sudo)." >&2
  exit 1
fi

# Resolve project root (directory containing this script is deploy/)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "[INFO] Using project root: ${PROJECT_ROOT}"

echo "[STEP] Installing Docker, docker-compose, Nginx, and Git (if needed)"
apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get install -y \
  docker.io docker-compose nginx git

systemctl enable --now docker

echo "[STEP] Ensuring Docker Compose stack is managed via systemd"
SERVICE_PATH="/etc/systemd/system/with-persona-docker-compose.service"
cp "${PROJECT_ROOT}/deploy/with-persona-docker-compose.service" "${SERVICE_PATH}"

# Point WorkingDirectory to this project on the droplet
sed -i "s|^WorkingDirectory=.*|WorkingDirectory=${PROJECT_ROOT}|" "${SERVICE_PATH}"

systemctl daemon-reload
systemctl enable --now with-persona-docker-compose.service

echo "[STEP] Configuring Nginx for domain ${APP_DOMAIN}"
NGINX_SITE="/etc/nginx/sites-available/withpersona.conf"
cp "${PROJECT_ROOT}/deploy/nginx-with-persona.conf" "${NGINX_SITE}"

# Replace server_name line with the desired domain
sed -i "s/server_name .*/server_name ${APP_DOMAIN};/" "${NGINX_SITE}"

ln -sf "${NGINX_SITE}" /etc/nginx/sites-enabled/withpersona.conf

nginx -t
systemctl reload nginx

echo "[DONE] Deployment completed. Summary:"
cat <<EOF
- Project root: ${PROJECT_ROOT}
- Docker Compose stack: managed by systemd unit with-persona-docker-compose.service
- App URL (HTTP): http://${APP_DOMAIN}

If you want HTTPS, run on the droplet:
  apt-get install -y certbot python3-certbot-nginx
  certbot --nginx -d ${APP_DOMAIN}
EOF
