#!/usr/bin/env bash
# Manage WeOwn DigitalOcean droplets via doctl
# Requires: doctl authenticated (doctl auth init), or DIGITALOCEAN_ACCESS_TOKEN set
#
# Usage:
#   ./manage-droplets.sh list                       # list all droplets with IPs
#   ./manage-droplets.sh ssh-keys                   # list all SSH keys in your DO account
#   ./manage-droplets.sh add-ssh-key <key-id>       # add a key to every droplet (via cloud rebuild — not live injection)
#   ./manage-droplets.sh show-ssh-keys <droplet>    # show which SSH keys a specific droplet was created with
#   ./manage-droplets.sh exec <tag> <command>       # run a shell command on all droplets with a given tag
#   ./manage-droplets.sh deploy <tag> <script>      # scp a local script and run it on all droplets with a tag
#   ./manage-droplets.sh status <tag>               # docker ps + uptime on all droplets with a tag
#   ./manage-droplets.sh rotate-authorized-keys     # replace ~/.ssh/authorized_keys on all tagged droplets
#
# Note: DigitalOcean does not support live SSH key injection via API — keys are embedded at
# droplet creation via cloud-init. To distribute a new key to running droplets, use the
# rotate-authorized-keys subcommand which pushes it directly over your existing SSH session.
#
# Compliance: NIST PR.AC, CIS 5.1, ISO A.8.2
set -euo pipefail

# ── helpers ──────────────────────────────────────────────────────────────────

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BOLD='\033[1m'; NC='\033[0m'
info()    { echo -e "${GREEN}==>${NC} $*"; }
warn()    { echo -e "${YELLOW}WARN:${NC} $*"; }
die()     { echo -e "${RED}ERROR:${NC} $*" >&2; exit 1; }
heading() { echo -e "\n${BOLD}$*${NC}"; }

check_doctl() {
  command -v doctl &>/dev/null || die "doctl not installed. brew install doctl"
  doctl account get &>/dev/null       || die "doctl not authenticated. Run: doctl auth init"
}

# Get the IP for a droplet by name or tag (returns first match for tag)
get_ip() {
  local target="$1"
  doctl compute droplet list --format Name,PublicIPv4 --no-header \
    | awk -v t="$target" '$1 == t || $1 ~ t { print $2; exit }'
}

# Get all IPs for droplets matching a tag
get_ips_by_tag() {
  local tag="$1"
  doctl compute droplet list --tag-name "$tag" --format PublicIPv4 --no-header \
    | grep -v '^$'
}

# Get all IPs across all droplets
get_all_ips() {
  doctl compute droplet list --format PublicIPv4 --no-header | grep -v '^$'
}

# SSH with consistent options
do_ssh() {
  local ip="$1"; shift
  ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -o BatchMode=yes "root@${ip}" "$@"
}

# ── subcommands ───────────────────────────────────────────────────────────────

cmd_list() {
  check_doctl
  heading "All WeOwn Droplets"
  printf '%-30s %-18s %-10s %-12s %s\n' NAME PUBLIC-IP REGION SIZE STATUS
  printf '%-30s %-18s %-10s %-12s %s\n' "----" "----" "----" "----" "----"
  doctl compute droplet list \
    --format Name,PublicIPv4,Region,Size,Status \
    --no-header
}

cmd_ssh_keys() {
  check_doctl
  heading "SSH Keys in your DigitalOcean account"
  printf '%-12s %-40s %s\n' ID NAME FINGERPRINT
  printf '%-12s %-40s %s\n' "----" "----" "----"
  doctl compute ssh-key list --format ID,Name,Fingerprint --no-header
}

cmd_show_ssh_keys() {
  check_doctl
  local droplet="${1:-}"
  [[ -z "$droplet" ]] && die "Usage: $0 show-ssh-keys <droplet-name>"

  heading "SSH keys configured at creation for: $droplet"
  local id
  id=$(doctl compute droplet list --format Name,ID --no-header \
    | awk -v d="$droplet" '$1 == d { print $2 }')
  [[ -z "$id" ]] && die "Droplet '$droplet' not found"

  doctl compute droplet get "$id" --format Name,VCPUs,Memory --no-header
  echo ""
  info "Keys embedded via cloud-init (from DO account):"
  doctl compute ssh-key list --format ID,Name,Fingerprint --no-header
  warn "DO API does not expose which specific keys were injected at create time."
  warn "To see live authorized_keys on the droplet, run:"
  echo "  $0 exec weown-ai 'cat ~/.ssh/authorized_keys'"
}

cmd_exec() {
  check_doctl
  local tag="${1:-}"; local cmd="${2:-}"
  [[ -z "$tag" || -z "$cmd" ]] && die "Usage: $0 exec <tag> <command>"

  local ips
  mapfile -t ips < <(get_ips_by_tag "$tag")
  [[ ${#ips[@]} -eq 0 ]] && die "No droplets found with tag: $tag"

  heading "Running on ${#ips[@]} droplet(s) [tag=$tag]: $cmd"
  for ip in "${ips[@]}"; do
    local name
    name=$(doctl compute droplet list --format Name,PublicIPv4 --no-header \
      | awk -v i="$ip" '$2 == i { print $1 }')
    echo -e "\n${BOLD}── $name ($ip) ──${NC}"
    do_ssh "$ip" "$cmd" || warn "Command failed on $ip"
  done
}

cmd_deploy() {
  check_doctl
  local tag="${1:-}"; local script="${2:-}"
  [[ -z "$tag" || -z "$script" ]] && die "Usage: $0 deploy <tag> <local-script>"
  [[ ! -f "$script" ]] && die "Script not found: $script"

  local ips
  mapfile -t ips < <(get_ips_by_tag "$tag")
  [[ ${#ips[@]} -eq 0 ]] && die "No droplets found with tag: $tag"

  local remote_path
  remote_path="/tmp/weown-deploy-$(basename "$script")"
  heading "Deploying $(basename "$script") to ${#ips[@]} droplet(s) [tag=$tag]"
  for ip in "${ips[@]}"; do
    local name
    name=$(doctl compute droplet list --format Name,PublicIPv4 --no-header \
      | awk -v i="$ip" '$2 == i { print $1 }')
    echo -e "\n${BOLD}── $name ($ip) ──${NC}"
    scp -o StrictHostKeyChecking=no -o ConnectTimeout=10 "$script" "root@${ip}:${remote_path}"
    do_ssh "$ip" "chmod +x ${remote_path} && ${remote_path}; rm -f ${remote_path}" \
      || warn "Deploy failed on $ip"
  done
}

cmd_status() {
  check_doctl
  local tag="${1:-weown-ai}"

  local ips
  mapfile -t ips < <(get_ips_by_tag "$tag")
  [[ ${#ips[@]} -eq 0 ]] && die "No droplets found with tag: $tag"

  heading "Status of ${#ips[@]} droplet(s) [tag=$tag]"
  for ip in "${ips[@]}"; do
    local name
    name=$(doctl compute droplet list --format Name,PublicIPv4 --no-header \
      | awk -v i="$ip" '$2 == i { print $1 }')
    echo -e "\n${BOLD}── $name ($ip) ──${NC}"
    do_ssh "$ip" '
      echo "  Uptime:   $(uptime -p)"
      echo "  Load:     $(cut -d" " -f1-3 /proc/loadavg)"
      echo "  Mem free: $(free -h | awk "/^Mem/ {print \$7}")"
      echo "  Disk:     $(df -h / | awk "NR==2 {print \$3\"/\"\$2\" (\"\$5\" used)\"}")"
      echo ""
      docker ps --format "  {{.Names}}\t{{.Image}}\t{{.Status}}" 2>/dev/null || echo "  (docker not running)"
    ' || warn "Could not reach $ip"
  done
}

cmd_rotate_authorized_keys() {
  check_doctl
  local tag="${1:-weown-ai}"

  heading "Rotate ~/.ssh/authorized_keys on all droplets [tag=$tag]"
  warn "This will REPLACE authorized_keys on every matched droplet."
  warn "Make sure your current key is in the new file before proceeding."
  echo ""

  # Build the new authorized_keys from all keys in the DO account
  info "Fetching all SSH public keys from your DigitalOcean account..."
  local tmpfile
  tmpfile=$(mktemp)
  trap 'rm -f "$tmpfile"' EXIT

  while IFS=$'\t' read -r key_id key_name _fp; do
    local pubkey
    pubkey=$(doctl compute ssh-key get "$key_id" --format PublicKey --no-header)
    echo "# $key_name (DO key ID $key_id)" >> "$tmpfile"
    echo "$pubkey" >> "$tmpfile"
  done < <(doctl compute ssh-key list --format ID,Name,Fingerprint --no-header | tr ' ' '\t')

  echo ""
  info "New authorized_keys content:"
  cat "$tmpfile"
  echo ""
  read -rp "Deploy this to all droplets tagged '$tag'? [y/N] " confirm
  [[ "$confirm" != "y" && "$confirm" != "Y" ]] && die "Aborted."

  local ips
  mapfile -t ips < <(get_ips_by_tag "$tag")
  [[ ${#ips[@]} -eq 0 ]] && die "No droplets found with tag: $tag"

  for ip in "${ips[@]}"; do
    local name
    name=$(doctl compute droplet list --format Name,PublicIPv4 --no-header \
      | awk -v i="$ip" '$2 == i { print $1 }')
    echo -e "\n${BOLD}── $name ($ip) ──${NC}"
    scp -o StrictHostKeyChecking=no -o ConnectTimeout=10 "$tmpfile" "root@${ip}:/tmp/authorized_keys.new"
    do_ssh "$ip" '
      mkdir -p ~/.ssh
      chmod 700 ~/.ssh
      cp ~/.ssh/authorized_keys ~/.ssh/authorized_keys.bak 2>/dev/null || true
      mv /tmp/authorized_keys.new ~/.ssh/authorized_keys
      chmod 600 ~/.ssh/authorized_keys
      echo "  Done. Backup saved as authorized_keys.bak"
    ' || warn "Failed on $ip — original keys preserved"
  done

  info "Rotation complete. Verify SSH access before closing this session."
}

# ── dispatch ──────────────────────────────────────────────────────────────────

SUBCOMMAND="${1:-help}"
shift || true

case "$SUBCOMMAND" in
  list)                  cmd_list ;;
  ssh-keys)              cmd_ssh_keys ;;
  show-ssh-keys)         cmd_show_ssh_keys "$@" ;;
  exec)                  cmd_exec "$@" ;;
  deploy)                cmd_deploy "$@" ;;
  status)                cmd_status "$@" ;;
  rotate-authorized-keys) cmd_rotate_authorized_keys "$@" ;;
  help|--help|-h)
    echo ""
    echo "Usage: $(basename "$0") <subcommand> [args]"
    echo ""
    echo "Subcommands:"
    echo "  list                           List all droplets with IPs and status"
    echo "  ssh-keys                       List all SSH keys in your DO account"
    echo "  show-ssh-keys <droplet>        Show authorized_keys on a specific droplet"
    echo "  exec <tag> <command>           Run a command on all droplets with a tag"
    echo "  deploy <tag> <script>          Copy and run a script on all droplets with a tag"
    echo "  status [tag]                   Docker + system status (default tag: weown-ai)"
    echo "  rotate-authorized-keys [tag]   Sync DO account SSH keys to all droplets"
    echo ""
    echo "Examples:"
    echo "  $(basename "$0") list"
    echo "  $(basename "$0") status weown-ai"
    echo "  $(basename "$0") exec weown-ai 'docker ps'"
    echo "  $(basename "$0") exec burnedout-xyz 'cat ~/.ssh/authorized_keys'"
    echo "  $(basename "$0") deploy weown-ai ./scripts/deploy.sh"
    echo "  $(basename "$0") rotate-authorized-keys weown-ai"
    echo ""
    ;;
  *)
    die "Unknown subcommand: $SUBCOMMAND. Run '$0 help' for usage."
    ;;
esac
