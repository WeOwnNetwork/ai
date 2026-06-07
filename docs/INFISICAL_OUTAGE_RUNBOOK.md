# Infisical Outage Runbook

Emergency procedures for when Infisical Cloud is unavailable.

## Detection

### Symptoms

- `deploy.sh` fails with `infisical run` errors
- `backup.sh` fails (cannot inject Spaces credentials)
- Container restarts fail (`docker compose up` under `infisical run` fails)
- Daily backup cron silently fails (check `/var/log/<project>-backup.log`)

### Verification

```bash
# Check Infisical status page (JSON API — requires jq)
curl -s https://status.infisical.com/api/v2/status.json | jq -r '.status.description'

# Check Infisical API directly
curl -s https://app.infisical.com/api/v1/auth/universal-auth/login \
  -H "Content-Type: application/json" \
  -d '{"clientId":"test","clientSecret":"test"}' \
  -w "%{http_code}" -o /dev/null
# Expected: 401 (auth failure, but API is up)
# Outage: connection timeout or 5xx
```

## Impact Assessment

### What Breaks

- **Deployments** — Cannot run `deploy.sh` (requires `infisical run`)
- **Backups** — Cannot run `backup.sh` (requires Spaces credentials from Infisical)
- **Restores** — Cannot run `restore.sh` (requires Spaces credentials from Infisical)
- **Container restarts** — Cannot restart containers (requires `infisical run`)
- **Secret rotation** — Cannot rotate Machine Identity secrets

### What Still Works

- **Running containers** — Already-started containers continue running. Secrets injected at startup via `infisical run` persist in the container's process environment for the lifetime of that container instance; they are not re-fetched on each request. Containers keep operating normally until they are recreated or restarted (at which point `infisical run` is needed again).
- **Application functionality** — Services (e.g. AnythingLLM, Caddy, or whichever app your template runs) work normally
- **TLS certificates** — Caddy manages certs independently
- **Network connectivity** — Firewall, DNS, reserved IP all work
- **Local backups** — Backups already on the droplet are accessible

## Emergency Procedures

### 1. Emergency Deployment (Without Infisical)

> **Template-agnostic note:** Adapt service names, variable names, and health endpoints to your template. See your template's `.env.example` and `compose.yaml` for the authoritative list.

**Use only when:** You must deploy changes during an Infisical outage.

**Prerequisites:**

- SSH access to the droplet
- Knowledge of required secrets (retrieve from secure storage, not git)

**Procedure:**

```bash
# 1. SSH to the droplet
ssh root@<droplet-ip>

# 2. Navigate to the app directory
cd /opt/<project_name>

# 3. Create a temporary .env file (DO NOT COMMIT THIS)
#    Example below is for the AnythingLLM template. For other templates,
#    copy the variables from your template's .env.example instead.
cat > .env.emergency <<'EOF'
JWT_SECRET=<retrieve-from-secure-storage>
OPENROUTER_API_KEY=<retrieve-from-secure-storage>
ANYTHINGLLM_IMAGE=<current-image-ref>
ADMIN_EMAIL=<admin-email>
SPACES_ACCESS_KEY=<retrieve-from-secure-storage>
SPACES_SECRET_KEY=<retrieve-from-secure-storage>
EOF

chmod 600 .env.emergency

# 4. Run docker compose with the emergency env file
docker compose --env-file .env.emergency up -d

# 5. Verify the deployment (replace with your template's health endpoint)
curl -f <health-endpoint>

# 6. Remove the emergency env file immediately after use
rm .env.emergency
```

**⚠️ Security Warning:**

- The `.env.emergency` file contains secrets in plaintext
- Delete it immediately after deployment
- Never commit it to git
- Log the incident for post-mortem review

### 2. Emergency Backup (Local Only)

> **Template-agnostic note:** Adapt service names and volume names to your template. See your template's `backup.sh` for the authoritative list.

**Use when:** Infisical is down and you need to create a backup before making changes.

**Procedure:**

```bash
# 1. SSH to the droplet
ssh root@<droplet-ip>

# 2. Navigate to the app directory
cd /opt/<project_name>

# 3. Create a local backup (no remote upload)
mkdir -p backups
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_NAME="<project_name>_backup_$TIMESTAMP"
WORK_DIR="backups/$BACKUP_NAME"

mkdir -p "$WORK_DIR"

# 4. Backup primary app storage volume
#    (AnythingLLM example — use the volume name from your template's backup.sh)
docker run --rm \
  -v "<project_name>_storage:/data:ro" \
  -v "$PWD/$WORK_DIR:/backup" \
  alpine:3.19 \
  tar czf /backup/anythingllm_storage.tar.gz -C /data .

# 5. Backup Caddy data volume (optional — only if your template includes Caddy)
docker run --rm \
  -v "<project_name>_caddy_data:/data:ro" \
  -v "$PWD/$WORK_DIR:/backup" \
  alpine:3.19 \
  tar czf /backup/caddy_data.tar.gz -C /data .

# 6. Backup configuration files
cp Caddyfile "$WORK_DIR/"
cp compose.yaml "$WORK_DIR/"
docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}' > "$WORK_DIR/containers.txt"

# 7. Compress the backup
cd backups
tar czf "${BACKUP_NAME}.tar.gz" "$BACKUP_NAME"
rm -rf "$BACKUP_NAME"

# 8. Verify the backup
ls -lh "${BACKUP_NAME}.tar.gz"
```

**Note:** This backup is local only. Upload to DO Spaces manually when Infisical is back online.

### 3. Emergency Restore (From Local Backup)

> **Template-agnostic note:** Adapt service names and volume names to your template. See your template's `backup.sh` for the authoritative list.

**Use when:** You need to restore from a backup that's already on the droplet.

**Procedure:**

```bash
# 1. SSH to the droplet
ssh root@<droplet-ip>

# 2. Navigate to the app directory
cd /opt/<project_name>

# 3. List available backups
ls -lh backups/*.tar.gz

# 4. Stop the target service (replace <service-name> per your template)
docker compose stop <service-name>

# 5. Extract the backup
cd backups
BACKUP_NAME="<backup-name-without-.tar.gz>"
tar xzf "${BACKUP_NAME}.tar.gz"

# 6. Clear target volume contents before restoring (prevents stale files)
docker run --rm -v "<project_name>_storage:/data" alpine:3.19 sh -c "rm -rf /data/*"

# 7. Restore primary app storage volume
#    (AnythingLLM example — use the volume/tarball name from your template's backup.sh)
docker run --rm \
  -v "<project_name>_storage:/data" \
  -v "$PWD/$BACKUP_NAME:/backup:ro" \
  alpine:3.19 \
  tar xzf /backup/anythingllm_storage.tar.gz -C /data

# 8. Restore Caddy data volume (optional — only if your template includes Caddy)
if [ -f "$BACKUP_NAME/caddy_data.tar.gz" ]; then
  docker run --rm -v "<project_name>_caddy_data:/data" alpine:3.19 sh -c "rm -rf /data/*"
  docker run --rm \
    -v "<project_name>_caddy_data:/data" \
    -v "$PWD/$BACKUP_NAME:/backup:ro" \
    alpine:3.19 \
    tar xzf /backup/caddy_data.tar.gz -C /data
fi

# 9. Restore configuration files
cp "$BACKUP_NAME/Caddyfile" ../Caddyfile
cp "$BACKUP_NAME/compose.yaml" ../compose.yaml

# 10. Clean up
rm -rf "$BACKUP_NAME"

# 11. Start the service (replace <service-name> per your template)
cd ..
docker compose start <service-name>

# 12. Verify (replace with your template's health endpoint)
curl -f <health-endpoint>
```

### 4. Emergency Restore (From DO Spaces)

> **Template-agnostic note:** Adapt service names and volume names to your template. See your template's `backup.sh` for the authoritative list.

**Use when:** You need to restore from a backup in DO Spaces, but Infisical is down.

**Prerequisites:**

- DO Spaces credentials (retrieve from secure storage)
- AWS CLI installed on the droplet

**Procedure:**

```bash
# 1. SSH to the droplet
ssh root@<droplet-ip>

# 2. Navigate to the app directory
cd /opt/<project_name>

# 3. Retrieve Spaces credentials from secure storage (do NOT export them).
#    Store them in shell variables scoped to the aws invocations below.
SPACES_ACCESS_KEY=<retrieve-from-secure-storage>
SPACES_SECRET_KEY=<retrieve-from-secure-storage>

# 4. List available backups in Spaces (credentials scoped to this command)
AWS_ACCESS_KEY_ID="$SPACES_ACCESS_KEY" AWS_SECRET_ACCESS_KEY="$SPACES_SECRET_KEY" \
  aws s3 ls s3://weown-prod-backups/<project_name>/ \
  --endpoint-url https://atl1.digitaloceanspaces.com

# 5. Download the backup (credentials scoped to this command)
mkdir -p backups
AWS_ACCESS_KEY_ID="$SPACES_ACCESS_KEY" AWS_SECRET_ACCESS_KEY="$SPACES_SECRET_KEY" \
  aws s3 cp s3://weown-prod-backups/<project_name>/<backup-name>.tar.gz \
  backups/ \
  --endpoint-url https://atl1.digitaloceanspaces.com

# 6. Clear the credential variables immediately
unset SPACES_ACCESS_KEY SPACES_SECRET_KEY

# 7. Follow the local restore procedure (section 3, steps 4-12)
```

### 5. Container Restart (Without Infisical)

> **Template-agnostic note:** Adapt service names and health endpoints to your template. See your template's `compose.yaml` for the authoritative list.

**Use when:** A container has crashed and needs to be restarted during an Infisical outage.

**Procedure:**

```bash
# 1. SSH to the droplet
ssh root@<droplet-ip>

# 2. Navigate to the app directory
cd /opt/<project_name>

# 3. Check container status
docker compose ps

# 4. Restart the specific container
#    Restarts reuse the env vars that were injected when the container was
#    originally started; they are not re-fetched from Infisical.
docker compose restart <service-name>

# 5. Verify (replace with your template's health endpoint)
docker compose ps
curl -f <health-endpoint>
```

**Note:** This only works if the container was previously started with `infisical run` and its process environment still holds the injected secrets. If the container was recreated (e.g. image change, `docker compose up -d --force-recreate`, or host reboot), the env vars are gone and you must use the emergency deployment procedure (section 1).

## Recovery (When Infisical Comes Back)

### 1. Verify Infisical is Operational

```bash
# Check Infisical status (JSON API — requires jq)
curl -s https://status.infisical.com/api/v2/status.json | jq -r '.status.description'

# Test authentication
infisical login
infisical whoami
```

### 2. Resume Normal Operations

```bash
# Test deployment
./scripts/deploy.sh root@<droplet-ip>

# Test backup
./scripts/backup.sh root@<droplet-ip>

# Verify daily cron is working
ssh root@<droplet-ip> 'tail -20 /var/log/<project>-backup.log'
```

### 3. Upload Emergency Backups (If Any)

If you created local-only backups during the outage:

```bash
# SSH to the droplet
ssh root@<droplet-ip>

# Navigate to backups directory
cd /opt/<project_name>/backups

# Upload to Spaces (requires Infisical)
source /opt/<project_name>/.infisical-auth.env
export INFISICAL_TOKEN="$(infisical login --method=universal-auth \
  --client-id="$INFISICAL_CLIENT_ID" \
  --client-secret="$INFISICAL_CLIENT_SECRET" \
  --plain --silent)"

infisical run --projectId=<project-id> --env=prod -- \
  aws s3 cp <backup-name>.tar.gz \
  s3://weown-prod-backups/<project_name>/ \
  --endpoint-url https://atl1.digitaloceanspaces.com
```

### 4. Post-Incident Review

Document the incident:

- **When:** Start and end times
- **Duration:** Total outage duration
- **Impact:** What broke, what worked
- **Actions taken:** Which emergency procedures were used
- **Lessons learned:** What could be improved

Update this runbook if any procedures need refinement.

## Prevention & Mitigation

### 1. Monitoring

Set up monitoring for Infisical availability:

```bash
# Add to your monitoring system (e.g., UptimeRobot, Pingdom)
# URL: https://app.infisical.com/api/v1/auth/universal-auth/login
# Method: POST
# Expected: 401 (auth failure, but API is up)
# Alert on: connection timeout or 5xx errors
```

### 2. Secret Backup Strategy

Maintain a secure backup of critical secrets:

- **Password manager** (1Password, Bitwarden, etc.)
  - Store all Infisical secrets
  - Update when secrets change
  - Share with team via secure channels

- **Encrypted file** (age, sops, etc.)
  - Encrypt a JSON file with all secrets
  - Store in a secure location (not git)
  - Decrypt only during emergencies

### 3. Regular Testing

Test emergency procedures quarterly:

1. Simulate an Infisical outage (block Infisical API via firewall)
2. Perform an emergency deployment
3. Perform an emergency backup
4. Perform an emergency restore
5. Document any issues and update this runbook

### 4. Communication Plan

Establish a communication plan for Infisical outages:

- **Who to notify:** Team lead, on-call engineer
- **How to notify:** Slack, email, SMS
- **Escalation path:** If outage lasts > 1 hour, > 4 hours, > 24 hours

### 5. Alternative Secrets Manager

Consider a secondary secrets manager for critical deployments:

- **HashiCorp Vault** (self-hosted)
- **AWS Secrets Manager**
- **Azure Key Vault**

This adds complexity but provides redundancy for mission-critical systems.

## Quick Reference

| Scenario | Procedure | Section |
|----------|-----------|---------|
| Must deploy during outage | Emergency deployment | 1 |
| Need backup before changes | Emergency backup (local) | 2 |
| Restore from local backup | Emergency restore (local) | 3 |
| Restore from Spaces backup | Emergency restore (Spaces) | 4 |
| Container crashed | Container restart | 5 |
| Infisical is back online | Recovery procedures | Recovery |

## Related Documentation

- [DEPLOYMENT_GUIDE.md](../anythingllm-docker/DEPLOYMENT_GUIDE.md) — Normal deployment procedures
- [INFRA_BOOTSTRAP_PATTERN.md](INFRA_BOOTSTRAP_PATTERN.md) — Bootstrap pattern and security model
- [INCIDENT_RESPONSE.md](../.github/INCIDENT_RESPONSE.md) — General incident response procedures

## Revision History

| Date | Version | Changes |
|------|---------|---------|
| 2026-06-06 | 1.0 | Initial runbook |
