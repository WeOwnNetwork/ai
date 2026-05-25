#!/usr/bin/env bash
# int-p01 - DOKS → Docker Migration Bridge Script
#
# One-shot script that extracts AnythingLLM storage from the existing DOKS pod
# and packages it as a "skinny backup" tarball compatible with restore.sh.
#
# Pipeline:
#   1. kubectl exec into the AnythingLLM pod on DOKS
#   2. tar /app/server/storage into a local file
#   3. Wrap in the layout restore.sh expects:
#        int-p01_backup_<TS>/anythingllm_storage.tar.gz
#      then outer-tar to: int-p01_backup_<TS>.tar.gz
#   4. (Optional) upload to s3://weown-backups/int-p01/ via DO Spaces
#
# After this completes, restore onto the new droplet with:
#   ssh root@<droplet> 'cd /opt/intp01 && \
#     infisical run --projectId=<id> --env=prod -- ./restore.sh <BACKUP_NAME>'
#
# Usage:
#   ./migrate-from-doks.sh \
#     --kubeconfig ~/.kube/doks-int-p01 \
#     --namespace anythingllm \
#     --selector 'app.kubernetes.io/name=anythingllm' \
#     [--storage-path /app/server/storage] \
#     [--output-dir ./backups] \
#     [--upload-to-spaces]
#
# Required local tools: kubectl, tar
# Optional (for --upload-to-spaces): aws CLI + SPACES_ACCESS_KEY + SPACES_SECRET_KEY in env
set -euo pipefail

# --- Defaults (overridable via flags) -----------------------------------------
PROJECT_NAME="int-p01"
KUBECONFIG_PATH=""
NAMESPACE=""
SELECTOR=""
STORAGE_PATH="/app/server/storage"
OUTPUT_DIR=""
UPLOAD_TO_SPACES=false
SPACES_BUCKET="weown-backups"
SPACES_REGION="atl1"

# --- Parse flags --------------------------------------------------------------
usage() {
  sed -n '2,28p' "$0"
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --kubeconfig)       KUBECONFIG_PATH="$2"; shift 2 ;;
    --namespace)        NAMESPACE="$2"; shift 2 ;;
    --selector)         SELECTOR="$2"; shift 2 ;;
    --storage-path)     STORAGE_PATH="$2"; shift 2 ;;
    --output-dir)       OUTPUT_DIR="$2"; shift 2 ;;
    --upload-to-spaces) UPLOAD_TO_SPACES=true; shift ;;
    --spaces-bucket)    SPACES_BUCKET="$2"; shift 2 ;;
    --spaces-region)    SPACES_REGION="$2"; shift 2 ;;
    -h|--help)          usage ;;
    *) echo "ERROR: unknown flag: $1" >&2; usage ;;
  esac
done

# --- Validate -----------------------------------------------------------------
: "${KUBECONFIG_PATH:?--kubeconfig is required}"
: "${NAMESPACE:?--namespace is required}"
: "${SELECTOR:?--selector is required (e.g. 'app.kubernetes.io/name=anythingllm')}"

if [[ ! -f "$KUBECONFIG_PATH" ]]; then
  echo "ERROR: kubeconfig not found: $KUBECONFIG_PATH" >&2
  exit 1
fi

command -v kubectl >/dev/null || { echo "ERROR: kubectl not installed" >&2; exit 1; }

if [[ "$UPLOAD_TO_SPACES" == "true" ]]; then
  command -v aws >/dev/null || { echo "ERROR: aws CLI required for --upload-to-spaces" >&2; exit 1; }
  : "${SPACES_ACCESS_KEY:?SPACES_ACCESS_KEY must be set when --upload-to-spaces (fetch from Infisical: weown-anythingllm/prod)}"
  : "${SPACES_SECRET_KEY:?SPACES_SECRET_KEY must be set when --upload-to-spaces (fetch from Infisical: weown-anythingllm/prod)}"
fi

# Default output dir: ../backups relative to script
if [[ -z "$OUTPUT_DIR" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  OUTPUT_DIR="$(dirname "$SCRIPT_DIR")/backups"
fi
mkdir -p "$OUTPUT_DIR"

export KUBECONFIG="$KUBECONFIG_PATH"

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_NAME="${PROJECT_NAME}_backup_${TIMESTAMP}"
WORK_DIR="$OUTPUT_DIR/$BACKUP_NAME"
FINAL_ARCHIVE="$OUTPUT_DIR/${BACKUP_NAME}.tar.gz"

echo "==> Migration bridge: DOKS → Docker"
echo "    kubeconfig:      $KUBECONFIG_PATH"
echo "    namespace:       $NAMESPACE"
echo "    selector:        $SELECTOR"
echo "    storage path:    $STORAGE_PATH"
echo "    output dir:      $OUTPUT_DIR"
echo "    backup name:     $BACKUP_NAME"
echo "    upload to DO:    $UPLOAD_TO_SPACES"
echo ""

# --- Find the pod -------------------------------------------------------------
echo "==> Locating AnythingLLM pod..."
POD=$(kubectl -n "$NAMESPACE" get pod -l "$SELECTOR" \
  -o jsonpath='{.items[?(@.status.phase=="Running")].metadata.name}' | awk '{print $1}')

if [[ -z "$POD" ]]; then
  echo "ERROR: no Running pod found in namespace '$NAMESPACE' with selector '$SELECTOR'" >&2
  kubectl -n "$NAMESPACE" get pods -l "$SELECTOR" >&2 || true
  exit 1
fi
echo "    found pod: $POD"

# --- Stream the storage tarball back ------------------------------------------
mkdir -p "$WORK_DIR"
echo "==> Streaming $STORAGE_PATH from pod (this may take a few minutes)..."
# Run tar inside the pod, write the gzipped stream to the local file.
# We do NOT use `kubectl cp` because it does not preserve permissions reliably
# and is slower for nested storage trees; `kubectl exec | tar` is the canonical
# pattern for live-PV extraction.
kubectl -n "$NAMESPACE" exec "$POD" -- \
  tar czf - -C "$STORAGE_PATH" . \
  > "$WORK_DIR/anythingllm_storage.tar.gz"

SRC_SIZE=$(ls -lh "$WORK_DIR/anythingllm_storage.tar.gz" | awk '{print $5}')
echo "    captured storage: $WORK_DIR/anythingllm_storage.tar.gz ($SRC_SIZE)"

# --- Record source metadata (no secrets) --------------------------------------
echo "==> Recording source pod metadata..."
{
  echo "# DOKS source snapshot"
  echo "timestamp:   $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "kube_context: $(kubectl config current-context 2>/dev/null || echo unknown)"
  echo "namespace:   $NAMESPACE"
  echo "pod:         $POD"
  echo "selector:    $SELECTOR"
  echo "storage:     $STORAGE_PATH"
  echo ""
  echo "# AnythingLLM image (from running pod)"
  kubectl -n "$NAMESPACE" get pod "$POD" \
    -o jsonpath='image: {.spec.containers[0].image}{"\n"}' 2>/dev/null || true
} > "$WORK_DIR/source.txt"

# --- Wrap into the layout restore.sh expects ----------------------------------
# restore.sh extracts ${BACKUP_NAME}.tar.gz, then expects the inner directory
# ${BACKUP_NAME}/ containing anythingllm_storage.tar.gz (and optionally
# caddy_data.tar.gz, Caddyfile, compose.yaml — none of those exist on DOKS).
echo "==> Wrapping backup in the skinny-backup layout..."
( cd "$OUTPUT_DIR" && tar czf "${BACKUP_NAME}.tar.gz" "$BACKUP_NAME" )
rm -rf "$WORK_DIR"

FINAL_SIZE=$(ls -lh "$FINAL_ARCHIVE" | awk '{print $5}')
echo "    final archive:   $FINAL_ARCHIVE ($FINAL_SIZE)"

# --- Optional: upload to DO Spaces --------------------------------------------
if [[ "$UPLOAD_TO_SPACES" == "true" ]]; then
  echo "==> Uploading to DO Spaces (s3://${SPACES_BUCKET}/${PROJECT_NAME}/)..."
  AWS_ACCESS_KEY_ID="$SPACES_ACCESS_KEY" \
  AWS_SECRET_ACCESS_KEY="$SPACES_SECRET_KEY" \
  aws s3 cp "$FINAL_ARCHIVE" \
    "s3://${SPACES_BUCKET}/${PROJECT_NAME}/" \
    --endpoint-url "https://${SPACES_REGION}.digitaloceanspaces.com" \
    --quiet
  echo "    uploaded: s3://${SPACES_BUCKET}/${PROJECT_NAME}/${BACKUP_NAME}.tar.gz"
fi

echo ""
echo "=== MIGRATION BRIDGE COMPLETE ==="
echo ""
echo "Next step — restore onto the new droplet (run on the operator's laptop):"
echo ""
echo "  # 1. Copy the tarball to the droplet (or rely on the DO Spaces fetch in restore.sh)"
echo "  scp $FINAL_ARCHIVE root@<droplet-ip>:/opt/intp01/backups/"
echo ""
echo "  # 2. Trigger restore (must run inside infisical run so Spaces creds are available)"
echo "  ssh root@<droplet-ip> 'cd /opt/intp01 && \\"
echo "    infisical run --projectId=<infisical-project-id> --env=prod -- \\"
echo "    ./restore.sh ${BACKUP_NAME}'"
echo ""
echo "Source DOKS pod is UNCHANGED — rollback is just a DNS flip."
