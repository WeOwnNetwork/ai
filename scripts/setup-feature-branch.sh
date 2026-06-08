#!/usr/bin/env bash
# setup-feature-branch.sh — Create a new feature branch with integrated completed work
#
# This script automates the process of creating a new feature branch and merging
# relevant completed work from other branches. It reads WORK_LOG.md to understand
# what's been completed and suggests appropriate merges based on the task type.
#
# Usage:
#   ./setup-feature-branch.sh <branch-name> [options]
#
# Options:
#   --task <type>        Task type: deployment, template, docs, infrastructure (default: auto-detect)
#   --auto               Skip interactive prompts, use recommended merges
#   --dry-run            Show what would be done without making changes
#   --list               List available branches and exit
#   --help               Show this help message
#
# Examples:
#   ./setup-feature-branch.sh keycloak-deployment
#   ./setup-feature-branch.sh keycloak-deployment --task deployment --auto
#   ./setup-feature-branch.sh template-updates --task template --dry-run
#   ./setup-feature-branch.sh --list
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
WORK_LOG="$REPO_ROOT/WORK_LOG.md"
LOG_FILE="$REPO_ROOT/branch-setup.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
  echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*" | tee -a "$LOG_FILE"
}

success() {
  echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅${NC} $*" | tee -a "$LOG_FILE"
}

warn() {
  echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️${NC}  $*" | tee -a "$LOG_FILE"
}

error() {
  echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌${NC} $*" | tee -a "$LOG_FILE"
}

# Show help
show_help() {
  cat << 'EOF'
setup-feature-branch.sh — Create a new feature branch with integrated completed work

USAGE:
  ./setup-feature-branch.sh <branch-name> [options]

OPTIONS:
  --task <type>        Task type: deployment, template, docs, infrastructure (default: auto-detect)
  --auto               Skip interactive prompts, use recommended merges
  --dry-run            Show what would be done without making changes
  --list               List available branches and exit
  --help               Show this help message

TASK TYPES:
  deployment     New site deployment (merges: site-conf, site-sh, automated-deployment)
  template       Template updates (merges: site-conf, site-sh)
  docs           Documentation work (merges: outage-runbook)
  infrastructure Infrastructure changes (merges: site-conf, site-sh)
  all            Merge all completed work

EXAMPLES:
  ./setup-feature-branch.sh keycloak-deployment
  ./setup-feature-branch.sh keycloak-deployment --task deployment --auto
  ./setup-feature-branch.sh template-updates --task template --dry-run
  ./setup-feature-branch.sh --list

EOF
}

# Parse arguments
BRANCH_NAME=""
TASK_TYPE=""
AUTO_MODE=false
DRY_RUN=false
LIST_ONLY=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --task)
      [[ $# -ge 2 ]] || { error "--task requires a value"; exit 1; }
      TASK_TYPE="$2"; shift 2 ;;
    --auto) AUTO_MODE=true; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    --list) LIST_ONLY=true; shift ;;
    --help) show_help; exit 0 ;;
    -*) error "Unknown option: $1"; show_help; exit 1 ;;
    *)
      if [[ -z "$BRANCH_NAME" ]]; then
        BRANCH_NAME="$1"
      else
        error "Unexpected argument: $1"
        show_help
        exit 1
      fi
      shift
      ;;
  esac
done

# Validate arguments
if [[ "$LIST_ONLY" == "false" && -z "$BRANCH_NAME" ]]; then
  error "Branch name is required"
  show_help
  exit 1
fi

# Check if WORK_LOG.md exists
if [[ ! -f "$WORK_LOG" ]]; then
  warn "WORK_LOG.md not found at $WORK_LOG; creating an empty work log (gitignored)"
  : > "$WORK_LOG"
fi

# Get list of completed branches from WORK_LOG.md
get_completed_branches() {
  grep -E "^\*\*Branch:\*\* \`(feature|fix|docs|hotfix)/" "$WORK_LOG" | \
    sed -E 's/.*`((feature|fix|docs|hotfix)\/[^`]+)`.*/\1/' | \
    sort -u
}

# Get branch description from WORK_LOG.md
get_branch_description() {
  local branch="$1"
  local desc
  desc=$(grep -A 5 "^\*\*Branch:\*\* \`$branch\`" "$WORK_LOG" | \
    grep -E "^\*\*What:\*\*" | \
    sed -E 's/\*\*What:\*\* //' | \
    head -1 || true)
  echo "${desc:-No description available}"
}

# List available branches
list_branches() {
  echo "==================================================================="
  echo "  Available Completed Work"
  echo "==================================================================="
  echo ""

  local branches=$(get_completed_branches)

  if [[ -z "$branches" ]]; then
    warn "No completed branches found in WORK_LOG.md"
    return
  fi

  while IFS= read -r branch; do
    if git show-ref --verify --quiet "refs/heads/$branch" 2>/dev/null; then
      local desc=$(get_branch_description "$branch")
      echo -e "${GREEN}✓${NC} $branch"
      echo "  $desc"
      echo ""
    else
      warn "Branch $branch listed in WORK_LOG.md but not found locally"
    fi
  done <<< "$branches"
}

# Auto-detect task type from branch name
detect_task_type() {
  local name="$1"

  if [[ "$name" =~ (deployment|deploy|site|instance) ]]; then
    echo "deployment"
  elif [[ "$name" =~ (template|update|upgrade) ]]; then
    echo "template"
  elif [[ "$name" =~ (doc|guide|readme) ]]; then
    echo "docs"
  elif [[ "$name" =~ (infra|terraform|network) ]]; then
    echo "infrastructure"
  else
    echo "all"
  fi
}

# Get recommended merges for task type
get_recommended_merges() {
  local task_type="$1"
  local completed=$(get_completed_branches)

  case "$task_type" in
    deployment)
      echo "$completed" | grep -E "(site-conf|site-sh|automated-site-deployment)" || true
      ;;
    template)
      echo "$completed" | grep -E "(site-conf|site-sh)" || true
      ;;
    docs)
      echo "$completed" | grep -E "(outage-runbook)" || true
      ;;
    infrastructure)
      echo "$completed" | grep -E "(site-conf|site-sh)" || true
      ;;
    all)
      echo "$completed"
      ;;
    *)
      warn "Unknown task type: $task_type, merging all completed work"
      echo "$completed"
      ;;
  esac
}

# Main execution
if [[ "$LIST_ONLY" == "true" ]]; then
  list_branches
  exit 0
fi

# Normalize branch name — add feature/<dev>- prefix if missing
# Extract <dev> from current branch name (e.g., feature/mot-foo → mot)
CURRENT_DEV=$(git rev-parse --abbrev-ref HEAD 2>/dev/null | sed -nE 's|^(feature|fix|docs|hotfix)/([a-z0-9]+)-.*|\2|p')
CURRENT_DEV="${CURRENT_DEV:-$(whoami)}"  # fallback to username

if [[ ! "$BRANCH_NAME" =~ ^(feature|fix|docs|hotfix)/ ]]; then
  BRANCH_NAME="feature/${CURRENT_DEV}-${BRANCH_NAME}"
fi

log "Setting up feature branch: $BRANCH_NAME"

# Check if branch already exists
if git show-ref --verify --quiet "refs/heads/$BRANCH_NAME" 2>/dev/null; then
  error "Branch $BRANCH_NAME already exists"
  echo "  Use: git checkout $BRANCH_NAME"
  exit 1
fi

# Auto-detect task type if not specified
if [[ -z "$TASK_TYPE" ]]; then
  TASK_TYPE=$(detect_task_type "$BRANCH_NAME")
  log "Auto-detected task type: $TASK_TYPE"
fi

# Get recommended merges
RECOMMENDED=$(get_recommended_merges "$TASK_TYPE")

if [[ -z "$RECOMMENDED" ]]; then
  warn "No completed work found to merge"
  echo "  You can still create the branch from main and work on it"
fi

# Show what will be done
echo ""
echo "==================================================================="
echo "  Branch Setup Plan"
echo "==================================================================="
echo ""
echo "New branch: $BRANCH_NAME"
echo "Base: main"
echo "Task type: $TASK_TYPE"
echo ""

if [[ -n "$RECOMMENDED" ]]; then
  echo "Branches to merge:"
  while IFS= read -r branch; do
    desc=$(get_branch_description "$branch")
    echo -e "  ${GREEN}✓${NC} $branch"
    echo "    $desc"
  done <<< "$RECOMMENDED"
else
  echo "No branches to merge (starting from clean main)"
fi

echo ""

# Dry run mode
if [[ "$DRY_RUN" == "true" ]]; then
  log "[DRY RUN] Would create branch and merge listed branches"
  exit 0
fi

# Get user confirmation
if [[ "$AUTO_MODE" != "true" && -n "$RECOMMENDED" ]]; then
  read -p "Proceed with this setup? (y/n) " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    warn "Cancelled by user"
    exit 0
  fi
fi

# Create branch from main
log "Creating branch from main..."
if [[ -n "$(git status --porcelain)" ]]; then
  error "Working tree has uncommitted changes; commit/stash them before running this script"
  exit 1
fi
git checkout main
git pull --ff-only origin main
git checkout -b "$BRANCH_NAME"

# Merge branches
if [[ -n "$RECOMMENDED" ]]; then
  echo ""
  log "Merging completed work..."

  while IFS= read -r branch; do
    log "Merging $branch..."

    if ! git merge "$branch" --no-edit; then
      error "Merge conflict when merging $branch"
      echo ""
      echo "Resolve conflicts manually, then:"
      echo "  git add <resolved-files>"
      echo "  git commit"
      echo ""
      echo "Then re-run this script to continue merging remaining branches."
      exit 1
    fi

    success "Merged $branch"
  done <<< "$RECOMMENDED"
fi

# Final report
echo ""
echo "==================================================================="
echo "  Branch Setup Complete"
echo "==================================================================="
echo ""
echo "Branch: $BRANCH_NAME"
echo "Status: Ready for development"
echo ""

if [[ -n "$RECOMMENDED" ]]; then
  echo "Integrated work:"
  while IFS= read -r branch; do
    echo "  ✓ $branch"
  done <<< "$RECOMMENDED"
  echo ""
fi

echo "Next steps:"
echo "  1. Work on your feature"
echo "  2. Commit your changes"
echo "  3. Update WORK_LOG.md with progress"
echo "  4. When ready, batch with other work for PR submission"
echo ""

success "Branch $BRANCH_NAME is ready!"

log "Branch setup completed successfully"
