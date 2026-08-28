#!/usr/bin/env bash
# First-boot host prep for imait-bot-prod. Run as root on the droplet.
set -euo pipefail

if [[ ! -f /swapfile ]]; then
  fallocate -l 4G /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
fi
swapon /swapfile 2>/dev/null || true
grep -q '^/swapfile ' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq ca-certificates curl gnupg ufw

if ! command -v docker >/dev/null 2>&1; then
  curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
  sh /tmp/get-docker.sh
  rm -f /tmp/get-docker.sh
fi
systemctl enable --now docker

mkdir -p /etc/docker
cat >/etc/docker/daemon.json <<'EOF'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "storage-driver": "overlay2"
}
EOF
systemctl restart docker

ufw allow OpenSSH
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable

APP_DIR="${APP_DIR:-/opt/imait-bot}"
mkdir -p "$APP_DIR"
if [[ -f "$APP_DIR/.env.example" && ! -f "$APP_DIR/.env" ]]; then
  umask 077
  cp "$APP_DIR/.env.example" "$APP_DIR/.env"
  chmod 600 "$APP_DIR/.env"
  KEY="$(openssl rand -hex 32)"
  awk -v k="$KEY" '
    BEGIN { FS=OFS="=" }
    $1=="API_SERVER_KEY" { print $1"="k; next }
    { print }
  ' "$APP_DIR/.env" > "$APP_DIR/.env.tmp"
  mv "$APP_DIR/.env.tmp" "$APP_DIR/.env"
  unset KEY
  # Hermes drops uid after s6 setup; a root-only 0600 bind-mount is EACCES.
  chmod 644 "$APP_DIR/.env"
fi

echo "bootstrap-host: docker $(docker --version) — app dir $APP_DIR"
