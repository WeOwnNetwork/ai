#!/usr/bin/env bash
# sso — convenience wrapper for site operations
#
# This script provides a unified interface for common site operations.
# It reads INFISICAL_PROJECT_ID and INFISICAL_ENV from site.conf and
# auto-detects the droplet IP from tofu output.
#
# Usage:
#   ./site.sh <command> [args]
#
# Commands:
#   deploy [ip]              Deploy to droplet (auto-detects IP if not provided)
#   backup [ip]              Run backup (auto-detects IP if not provided)
#   restore [ip] <name>      Restore from backup
#   logs [ip]                Tail Docker logs via SSH
#   health [ip]              Check health endpoint (https://sso.weown.dev/health/ready)
#   ip                       Print droplet IP from tofu output
#   help                     Show this help message
#
# Examples:
#   ./site.sh deploy                    # Deploy to auto-detected IP
#   ./site.sh deploy 198.51.100.42      # Deploy to specific IP
#   ./site.sh backup                    # Backup to auto-detected IP
#   ./site.sh restore backup_20260606   # Restore from backup
#   ./site.sh logs                      # Tail Docker logs
#   ./site.sh health                    # Check Keycloak health via HTTPS
#   ./site.sh ip                        # Print droplet IP

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load site.conf (safe reader — only accepts UPPER_CASE=value lines)
if [[ -f "$SCRIPT_DIR/scripts/lib.sh" ]]; then
  source "$SCRIPT_DIR/scripts/lib.sh"
  load_site_conf "$SCRIPT_DIR/site.conf"
fi

get_droplet_ip() {
  local ip
  if [[ -d "$SCRIPT_DIR/terraform" ]]; then
    ip=$(cd "$SCRIPT_DIR/terraform" && tofu output -raw droplet_ip 2>/dev/null || echo "")
  fi

  if [[ -z "$ip" ]]; then
    echo "ERROR: could not get droplet IP from tofu output" >&2
    echo "       Run 'tofu output -raw droplet_ip' in terraform/ directory" >&2
    echo "       Or provide IP as argument: ./site.sh deploy <ip>" >&2
    exit 1
  fi

  echo "$ip"
}

cmd_deploy() {
  local ip="${1:-$(get_droplet_ip)}"
  echo "==> Deploying to $ip"
  exec "$SCRIPT_DIR/scripts/deploy.sh" "root@$ip"
}

cmd_backup() {
  local ip="${1:-$(get_droplet_ip)}"
  echo "==> Running backup on $ip"
  exec "$SCRIPT_DIR/scripts/backup.sh" "root@$ip"
}

cmd_restore() {
  local arg1="${1:-}"
  local arg2="${2:-}"
  local ip=""
  local backup_name=""

  # Detect whether $1 is an IP address or a backup name
  if [[ -z "$arg1" ]]; then
    echo "ERROR: backup name required" >&2
    echo "Usage: $0 restore [ip] <backup-name>" >&2
    echo "Example: $0 restore sso_backup_20260606_120000" >&2
    exit 1
  fi

  # Check if arg1 looks like an IP address (digits and dots)
  if [[ "$arg1" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    # arg1 is IP, arg2 must be backup name
    ip="$arg1"
    backup_name="$arg2"
    if [[ -z "$backup_name" ]]; then
      echo "ERROR: backup name required when IP is provided" >&2
      echo "Usage: $0 restore <ip> <backup-name>" >&2
      exit 1
    fi
  else
    # arg1 is backup name, auto-detect IP
    backup_name="$arg1"
    ip="$(get_droplet_ip)"
  fi

  echo "==> Restoring $backup_name on $ip"
  exec "$SCRIPT_DIR/scripts/restore.sh" "root@$ip" "$backup_name"
}

cmd_logs() {
  local ip="${1:-$(get_droplet_ip)}"
  echo "==> Tailing Docker logs on $ip"
  exec ssh -t "root@$ip" 'journalctl -u docker -f'
}

cmd_health() {
  local ip="${1:-$(get_droplet_ip)}"
  local url="https://sso.weown.dev/health/ready"

  echo -n "==> Checking health at $url ... "
  if curl -sf "$url" >/dev/null 2>&1; then
    echo "OK"
    exit 0
  else
    echo "FAIL"
    echo "    Tried: $url" >&2
    echo "    Try SSH check: ssh root@$ip 'docker compose -f /opt/sso/compose.yaml ps'"
    exit 1
  fi
}

cmd_ip() {
  get_droplet_ip
}

cmd_help() {
  cat <<EOF
sso — site operations wrapper

Usage: $0 <command> [args]

Commands:
  deploy [ip]              Deploy to droplet (auto-detects IP if not provided)
  backup [ip]              Run backup (auto-detects IP if not provided)
  restore [ip] <name>      Restore from backup
  logs [ip]                Tail Docker logs via SSH
  health [ip]              Check health endpoint (https://sso.weown.dev/health/ready)
  ip                       Print droplet IP from tofu output
  help                     Show this help message

Examples:
  $0 deploy                    # Deploy to auto-detected IP
  $0 deploy 198.51.100.42      # Deploy to specific IP
  $0 backup                    # Backup to auto-detected IP
  $0 restore backup_20260606   # Restore from backup
  $0 logs                      # Tail Docker logs
  $0 health                    # Check Keycloak health via HTTPS
  $0 ip                        # Print droplet IP

Environment:
  Reads INFISICAL_PROJECT_ID and INFISICAL_ENV from site.conf
  Env vars override site.conf values if set
EOF
}

# Main command dispatcher
case "${1:-help}" in
  deploy)  shift; cmd_deploy "$@" ;;
  backup)  shift; cmd_backup "$@" ;;
  restore) shift; cmd_restore "$@" ;;
  logs)    shift; cmd_logs "$@" ;;
  health)  shift; cmd_health "$@" ;;
  ip)      shift; cmd_ip ;;
  help|--help|-h) cmd_help ;;
  *)
    echo "ERROR: unknown command '$1'" >&2
    echo "Run '$0 help' for usage information" >&2
    exit 1
    ;;
esac
