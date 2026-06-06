## Problem

All docker templates (anythingllm-docker, wordpress-docker, keycloak-docker, searxng-docker, signoz-docker) use Infisical Cloud for runtime secret injection. If Infisical becomes unavailable:

- **Deployments fail** — `deploy.sh` cannot run `infisical run`
- **Backups fail** — `backup.sh` cannot inject Spaces credentials
- **Restores fail** — `restore.sh` cannot inject Spaces credentials
- **Container restarts fail** — Cannot recreate containers with secrets

This creates a **single point of failure** with no documented emergency procedures.

## Solution

Add a comprehensive **Infisical Outage Runbook** that provides:

1. **Detection** — How to verify Infisical is actually down (not just a local issue)
2. **Impact assessment** — What breaks and what still works
3. **Emergency procedures** — Step-by-step instructions for:
   - Manual deployment without Infisical (temporary `.env` file)
   - Local-only backup creation (no Spaces upload)
   - Emergency restore from local or Spaces backups
   - Container restart procedures
4. **Recovery** — What to do when Infisical comes back online
5. **Prevention** — Monitoring, secret backup strategies, regular testing

## Changes

### Added

- **`docs/INFISICAL_OUTAGE_RUNBOOK.md`** — 400+ line comprehensive runbook

### Modified

- **`anythingllm-docker/README.md`** — Added reference to outage runbook in Security section

## Key Procedures

### Emergency Deployment (Without Infisical)

```bash
# Create temporary .env file (DO NOT COMMIT)
cat > .env.emergency <<'EOF'
JWT_SECRET=<retrieve-from-secure-storage>
OPENROUTER_API_KEY=<retrieve-from-secure-storage>
ANYTHINGLLM_IMAGE=<current-image-ref>
# ... other secrets
EOF

chmod 600 .env.emergency
docker compose --env-file .env.emergency up -d
rm .env.emergency  # Delete immediately after use
```

### Emergency Backup (Local Only)

```bash
# Create backup without uploading to Spaces
docker run --rm \
  -v "<project>_storage:/data:ro" \
  -v "$PWD/backups:/backup" \
  alpine:3.19 \
  tar czf /backup/anythingllm_storage.tar.gz -C /data .
```

### Emergency Restore

```bash
# Restore from local backup
docker run --rm \
  -v "<project>_storage:/data" \
  -v "$PWD/backups:/backup:ro" \
  alpine:3.19 \
  tar xzf /backup/anythingllm_storage.tar.gz -C /data
```

## Security Considerations

The runbook includes explicit warnings about:

- **Never committing `.env.emergency` files** — Contains plaintext secrets
- **Deleting temporary files immediately** — After deployment completes
- **Retrieving secrets from secure storage** — Password manager, encrypted file, etc.
- **Logging incidents** — For post-mortem review

## Testing

The runbook recommends quarterly testing:

1. Simulate an Infisical outage (block API via firewall)
2. Perform an emergency deployment
3. Perform an emergency backup
4. Perform an emergency restore
5. Document issues and update the runbook

## Scope

This runbook applies to **all docker templates** that use Infisical runtime injection:

- anythingllm-docker
- wordpress-docker
- keycloak-docker
- searxng-docker
- signoz-docker
- sandbox-docker
- openclaw-docker

Each template's README should reference this runbook (can be done in follow-up PRs).

## Related Work

This addresses the **single-point-of-failure risk** identified during the site.conf implementation:

- PR #50: `feat(anythingllm-docker): site.conf — eliminate env var juggling for operators`
- PRs #44-47: site.conf implementations for other docker templates

The site.conf work improved operator UX but highlighted that Infisical is a critical dependency with no documented fallback procedures.

## Files Changed

**Added (1 file):**

- `docs/INFISICAL_OUTAGE_RUNBOOK.md` (402 lines)

**Modified (1 file):**

- `anythingllm-docker/README.md` (added reference to runbook)

## Stats

2 files changed, 414 insertions(+)

## Follow-up Work (Separate PRs)

- Add references to the runbook in other docker template READMEs (wordpress, keycloak, searxng, signoz, sandbox, openclaw)
- Set up Infisical availability monitoring (UptimeRobot, Pingdom, etc.)
- Implement quarterly testing drills
- Consider alternative secrets manager for redundancy (Vault, AWS Secrets Manager)
