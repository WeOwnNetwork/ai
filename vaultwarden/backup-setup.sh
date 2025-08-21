#!/bin/bash

# Vaultwarden Backup Setup Script
# Creates necessary secrets and deploys backup CronJob

set -euo pipefail

echo "🔧 Setting up Vaultwarden backup system..."

# Check if DigitalOcean token is provided
if [ -z "${DIGITALOCEAN_ACCESS_TOKEN:-}" ]; then
    echo "❌ DIGITALOCEAN_ACCESS_TOKEN environment variable is required"
    echo "💡 Get your token from: https://cloud.digitalocean.com/account/api/tokens"
    echo "💡 Usage: DIGITALOCEAN_ACCESS_TOKEN=your_token ./backup-setup.sh"
    exit 1
fi

# Create backup token secret
echo "📝 Creating backup token secret..."
kubectl create secret generic do-backup-token \
    --from-literal=token="$DIGITALOCEAN_ACCESS_TOKEN" \
    --namespace=vaultwarden \
    --dry-run=client -o yaml | kubectl apply -f -

# Deploy backup CronJob
echo "📅 Deploying backup CronJob..."
kubectl apply -f backup-cronjob.yaml

# Verify deployment
echo "✅ Verifying backup system..."
kubectl get cronjob vaultwarden-backup -n vaultwarden
kubectl describe cronjob vaultwarden-backup -n vaultwarden

echo ""
echo "🎉 Backup system deployed successfully!"
echo "📋 Backup schedule: Daily at 2 AM UTC"
echo "🗂️ Retention: 30 days"
echo "📊 Monitor with: kubectl get jobs -n vaultwarden"
