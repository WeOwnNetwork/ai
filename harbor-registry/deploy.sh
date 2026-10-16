#!/usr/bin/env bash
# Bootstrap Harbor v2.15.4 and the Caddy edge on the registry droplet.
# Run as root on the droplet, from this directory:
#   bash /opt/harbor-registry/deploy.sh
#
# Passwords are generated once into /root/harbor-registry-credentials.txt (mode 0600)
# and are not printed. Re-running does not rotate them and does not run upstream
# install.sh (that script executes `docker compose down -v`).
set -euo pipefail

HARBOR_VERSION=v2.15.4
HARBOR_SHA256=eeb899cf7b626c925790adba87db9008dd1d73a693a72442651b5bdece9805c6
HARBOR_URL="https://github.com/goharbor/harbor/releases/download/${HARBOR_VERSION}/harbor-online-installer-${HARBOR_VERSION}.tgz"
HARBOR_HOSTNAME="${HARBOR_HOSTNAME:-registry.weown.tools}"
APP_DIR=/opt/harbor-registry
HARBOR_DIR=/opt/harbor
CRED_FILE=/root/harbor-registry-credentials.txt

DOCKER_FPR=9DC858229FC7DD38854AE2D88D81803C0EBFCD88
DOCKER_VER=5:29.8.2-1~ubuntu.24.04~noble
CONTAINERD_VER=2.3.6-1~ubuntu.24.04~noble
COMPOSE_VER=5.6.0-1~ubuntu.24.04~noble

if [[ "$(id -u)" -ne 0 ]]; then
  echo "run deploy.sh as root on the droplet" >&2
  exit 1
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
if [[ "$SCRIPT_DIR" != "$APP_DIR" ]]; then
  mkdir -p "$APP_DIR"
  # Copy the package in place. Never copy a rendered harbor.yml from a workstation.
  tar -C "$SCRIPT_DIR" -cf - \
    --exclude harbor.yml \
    --exclude '*.tgz' \
    --exclude common \
    . | tar -C "$APP_DIR" -xf -
  exec bash "$APP_DIR/deploy.sh"
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq ca-certificates curl gnupg openssl ufw python3

if ! swapon --show | grep -q '/swapfile'; then
  if [[ ! -f /swapfile ]]; then
    fallocate -l 4G /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=4096
    chmod 600 /swapfile
    mkswap /swapfile
  fi
  swapon /swapfile
  grep -q '/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >>/etc/fstab
fi
sysctl -w vm.swappiness=10 >/dev/null
grep -q '^vm.swappiness' /etc/sysctl.d/99-harbor-swappiness.conf 2>/dev/null \
  || echo 'vm.swappiness=10' >/etc/sysctl.d/99-harbor-swappiness.conf

if ! docker compose version >/dev/null 2>&1; then
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc.new
  pubs=$(gpg --show-keys --with-colons /etc/apt/keyrings/docker.asc.new | awk -F: '$1 == "pub" { n++ } END { print n + 0 }')
  got=$(gpg --show-keys --with-colons /etc/apt/keyrings/docker.asc.new | awk -F: '$1 == "pub" { p = 1; next } p && $1 == "fpr" { print $10; exit }')
  if [[ "$pubs" != 1 || "$got" != "$DOCKER_FPR" ]]; then
    echo "Docker apt key: ${pubs} primary key(s), first fingerprint ${got}; expected ${DOCKER_FPR}" >&2
    rm -f /etc/apt/keyrings/docker.asc.new
    exit 1
  fi
  mv /etc/apt/keyrings/docker.asc.new /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
  # shellcheck disable=SC1091
  . /etc/os-release
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable" \
    >/etc/apt/sources.list.d/docker.list
  apt-get update -qq
  apt-get install -y -qq \
    "docker-ce=${DOCKER_VER}" "docker-ce-cli=${DOCKER_VER}" \
    "containerd.io=${CONTAINERD_VER}" "docker-compose-plugin=${COMPOSE_VER}"
  apt-mark hold docker-ce docker-ce-cli containerd.io docker-compose-plugin
fi
systemctl enable --now docker

ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw allow 443/udp
ufw --force enable

if [[ ! -s "$CRED_FILE" ]]; then
  umask 077
  admin_pw=$(openssl rand -hex 24)
  db_pw=$(openssl rand -hex 24)
  printf 'HARBOR_ADMIN_PASSWORD=%s\nHARBOR_DB_PASSWORD=%s\n' "$admin_pw" "$db_pw" >"$CRED_FILE"
  chmod 600 "$CRED_FILE"
  unset admin_pw db_pw
  echo "wrote ${CRED_FILE} (mode 0600). Read it on the box; it is not printed here."
fi

# Named volumes first, then bind them over the host paths Harbor uses.
mkdir -p /data/database /data/registry /data/job_logs
persist_volume() {
  local vol="$1" dest="$2" mp line
  docker volume create "$vol" >/dev/null
  mp=$(docker volume inspect -f '{{.Mountpoint}}' "$vol")
  mkdir -p "$dest"
  if ! mountpoint -q "$dest"; then
    mount --bind "$mp" "$dest"
  fi
  line="${mp} ${dest} none bind,nofail 0 0"
  grep -qxF "$line" /etc/fstab || echo "$line" >>/etc/fstab
}
persist_volume harbor_database /data/database
persist_volume harbor_registry /data/registry
persist_volume harbor_jobservice /data/job_logs

# Caddy compose also declares those volume names so they stay in source control.
# Create the edge volumes now; the container starts after Harbor's network exists.
docker volume create harbor-edge_caddy_data >/dev/null || true
docker volume create harbor-edge_caddy_config >/dev/null || true

if [[ ! -x "$HARBOR_DIR/prepare" ]]; then
  staged="${APP_DIR}/harbor-online-installer-${HARBOR_VERSION}.tgz"
  installer=$(mktemp --suffix=.tgz)
  if [[ -f "$staged" ]]; then
    cp "$staged" "$installer"
  else
    curl -fsSL --retry 5 --retry-all-errors --retry-delay 3 -A "Mozilla/5.0" -o "$installer" "$HARBOR_URL"
  fi
  echo "${HARBOR_SHA256}  ${installer}" | sha256sum -c -
  mkdir -p "$HARBOR_DIR"
  tar -xzf "$installer" -C "$HARBOR_DIR" --strip-components=1
  rm -f "$installer"
  chmod 0755 "$HARBOR_DIR/prepare" "$HARBOR_DIR/install.sh"
fi

# Render only when this host has not rendered before, so a re-run cannot
# rotate the database password out from under an initialized Postgres.
if [[ ! -f "$HARBOR_DIR/harbor.yml" ]]; then
  # shellcheck disable=SC1090
  set -a
  # shellcheck disable=SC1091
  . "$CRED_FILE"
  set +a
  : "${HARBOR_ADMIN_PASSWORD:?missing HARBOR_ADMIN_PASSWORD in ${CRED_FILE}}"
  : "${HARBOR_DB_PASSWORD:?missing HARBOR_DB_PASSWORD in ${CRED_FILE}}"
  umask 077
  sed \
    -e "s/__HARBOR_HOSTNAME__/${HARBOR_HOSTNAME}/g" \
    -e "s/__HARBOR_ADMIN_PASSWORD__/${HARBOR_ADMIN_PASSWORD}/g" \
    -e "s/__HARBOR_DB_PASSWORD__/${HARBOR_DB_PASSWORD}/g" \
    "$APP_DIR/harbor.yml.tmpl" >"$HARBOR_DIR/harbor.yml"
  chmod 600 "$HARBOR_DIR/harbor.yml"
  unset HARBOR_ADMIN_PASSWORD HARBOR_DB_PASSWORD
  if grep -q '__HARBOR_' "$HARBOR_DIR/harbor.yml"; then
    echo "harbor.yml still contains placeholders" >&2
    exit 1
  fi
fi

cd "$HARBOR_DIR"
# prepare writes docker-compose.yml and common/config. Do not use install.sh:
# it always runs `docker compose down -v`.
./prepare --with-trivy

python3 - <<'PY'
from pathlib import Path
import re
import sys
p = Path("/opt/harbor/docker-compose.yml")
text = p.read_text()
pat = re.compile(
    r"(?m)^[ \t]*ports:\s*\n(?:[ \t]*-[ \t]*['\"]?(?:[\d.]+:)?(?:8080:8080|8443:8443|443:443|80:80)['\"]?\s*\n)+"
)
new, n = pat.subn("", text)
if n < 1 and "8080:8080" in text:
    for i, line in enumerate(text.splitlines(), 1):
        if "8080" in line or line.strip() == "ports:":
            print("%d:%s" % (i, line))
    sys.exit("refusing to start Harbor: host port 8080 is still published and was not removed")
if "8080:8080" in new or "443:443" in new or re.search(r"(?m)^\s*-\s+80:80\s*$", new):
    sys.exit("refusing to start Harbor: a host port mapping remains in docker-compose.yml")
p.write_text(new)
print("unpublished Harbor proxy host ports (%d block(s))" % n)
PY

docker compose up -d

harbor_net=$(docker inspect -f '{{range $k, $v := .NetworkSettings.Networks}}{{$k}}{{"\n"}}{{end}}' nginx | head -n 1)
if [[ -z "$harbor_net" ]]; then
  echo "nginx container has no network; Harbor did not start" >&2
  exit 1
fi
umask 022
printf 'HARBOR_DOCKER_NETWORK=%s\n' "$harbor_net" >"$APP_DIR/.env"
chmod 644 "$APP_DIR/.env"

cd "$APP_DIR"
docker compose up -d

echo "Harbor and Caddy are up. Hostname ${HARBOR_HOSTNAME}."
echo "Admin password is in ${CRED_FILE} on this host. It was not printed."
