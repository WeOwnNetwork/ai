# Smoke Test Framework

Generic post-deployment verification framework for all docker templates.

## Overview

The smoke test framework provides standardized checks that run after deploying a site. It works across all template types (anythingllm, keycloak, wordpress, searxng, signoz, etc.) through a combination of generic checks and template-specific hooks.

**Design principles:**

- ~5 minutes execution time
- Idempotent (safe to run multiple times)
- No secrets in logs
- Clear pass/fail output with actionable error messages
- POSIX sh compatible (works on minimal systems)

## Usage

### Basic Usage (Generic Checks Only)

```bash
./scripts/smoke-test-framework.sh sites/mysite.example.com
```

This runs the generic checks (infrastructure, containers, backup) but skips application-specific checks.

### With Template-Specific Hooks

```bash
./scripts/smoke-test-framework.sh sites/mysite.example.com \
  anythingllm-docker/template/scripts/smoke-test-hooks.sh
```

This runs all generic checks plus AnythingLLM-specific checks (web interface, API health, collector container, etc.).

### Integration with deploy-new-site.sh

The smoke test runs automatically after deployment in Phase 5:

```bash
./scripts/deploy-new-site.sh --template anythingllm-docker --site-name mysite --domain mysite.example.com --admin-email admin@example.com
```

The deployment script will:

1. Deploy the site (Phases 1-4)
2. Run smoke test (Phase 5)
3. Report results

**Note:** Smoke test failures are advisory — they warn but don't fail the deployment. This allows deployment to succeed even if some checks fail (e.g., DNS not propagated yet).

## What It Checks

### Phase 1: Infrastructure (7 checks)

- SSH connectivity
- Cloud-init completion
- Docker service running
- Docker Compose available
- Infisical CLI installed
- Auth file exists at `/opt/<site>/.infisical-auth.env` (per-site directory)
- Auth file permissions (600)

### Phase 2: Containers (4 checks)

- All containers running
- No restart loops (<10 total restarts)
- Healthchecks passing
- No critical errors in logs

### Phase 3: Application-Specific (via hooks)

- Template-specific checks (e.g., AnythingLLM web interface, collector container)
- Skipped if no hooks provided

### Phase 4: Backup System (4 checks)

- Backup script exists
- Backup script executable
- Backup cron job configured
- Backup directory exists

## Creating Template-Specific Hooks

Each template can provide its own `smoke-test-hooks.sh` file with application-specific checks.

### Step 1: Create the Hook File

Create `<template>/template/scripts/smoke-test-hooks.sh`:

```bash
#!/bin/sh
# Template-specific smoke test hooks

run_template_specific_checks() {
  log_info "Running <template>-specific checks..."

  # Check 3.1: Application web interface
  log_info "Checking web interface..."
  http_code=$(curl -s -o /dev/null -w "%{http_code}" "http://${DROPLET_IP}:8080" 2>/dev/null || echo "000")
  
  if [ "$http_code" = "200" ] || [ "$http_code" = "302" ]; then
    log_pass "Web interface accessible (HTTP $http_code)"
  else
    log_fail "Web interface not accessible (HTTP $http_code)"
  fi

  # Check 3.2: Application API
  log_info "Checking API health..."
  api_response=$(curl -s "http://${DROPLET_IP}:8080/api/health" 2>/dev/null || echo "")
  
  if [ -n "$api_response" ]; then
    log_pass "API health endpoint responding"
  else
    log_fail "API health endpoint not responding"
  fi

  # Add more checks as needed...
}
```

### Step 2: Document in Template README

Add a section to `<template>/README.md`:

```markdown
## Smoke Test

After deployment, run the smoke test:

\`\`\`bash
./scripts/smoke-test-framework.sh sites/mysite.example.com \
  <template>/template/scripts/smoke-test-hooks.sh
\`\`\`

This checks:
- Generic infrastructure and container health
- <Template>-specific: web interface, API health, etc.
```

## Available Variables

Your hook function has access to these variables:

- `DROPLET_IP` — IP address of the droplet
- `REMOTE_SITE_DIR` — Remote path to site directory (e.g., `/opt/mysite`)
- `SITE_NAME` — Name of the site
- `log_info`, `log_pass`, `log_fail`, `log_skip` — Logging functions

## Exit Codes

- `0` — All tests passed
- `1` — One or more tests failed

## Examples

### AnythingLLM Hooks

See `anythingllm-docker/template/scripts/smoke-test-hooks.sh` for a complete example:

- Web interface check (HTTP 200/302)
- API health endpoint
- Collector container running
- Vector database accessible
- Workspace directory exists

### Minimal Hooks (Placeholder)

For templates without specific checks yet, create a minimal hook:

```bash
#!/bin/sh
run_template_specific_checks() {
  log_skip "No <template>-specific checks implemented yet"
}
```

## Validation Status

**What's validated:**

- ✅ Syntax validation (sh -n)
- ✅ POSIX sh compatible (no bashisms)
- ✅ Integration with deploy-new-site.sh
- ✅ Follows project conventions

**What's NOT validated:**

- ❌ End-to-end execution (no SSH access to deployed site)
- ❌ Real-world behavior (will test during Keycloak deployment)

## Troubleshooting

### SSH Connection Fails

```
[FAIL] SSH connectivity to 192.0.2.1
```

**Check:**

- SSH key configured in DigitalOcean
- SSH key in `~/.ssh/` or ssh-agent
- Firewall allows SSH (port 22)
- Droplet is running

### Cloud-init Not Completed

```
[FAIL] Cloud-init not completed
```

**Check:**

- Wait 5-10 minutes after droplet creation
- Check logs: `ssh root@<ip> 'cat /var/log/cloud-init.log'`
- Verify cloud-init script in terraform config

### Containers Not Running

```
[FAIL] Not all containers running (2/3)
```

**Check:**

- `ssh root@<ip> 'cd /opt/<site> && docker compose ps'`
- `ssh root@<ip> 'cd /opt/<site> && docker compose logs'`
- Verify auth file exists and has correct permissions

### Auth File Missing

```
[FAIL] Auth file missing (/opt/<site>/.infisical-auth.env)
```

**Check:**

- Cloud-init completed successfully
- Infisical credentials configured in terraform.tfvars
- Check cloud-init logs for errors
- Verify auth file location: `/opt/<site>/.infisical-auth.env` (per-site directory, not `/root/`)

## Related

- `deploy-new-site.sh` — Automated deployment script
- `site.sh` — Site management commands
- `template-validation` skill — Pre-deployment validation
- PR #68 — ADR-006 implementation (auth file, entrypoint wrapper)

## Template Coverage

All 7 templates have smoke test hooks:

| Template | Hooks | Checks |
|----------|-------|--------|
| anythingllm-docker | ✅ | Web UI, API health, collector, vector DB, workspace dir |
| keycloak-docker | ✅ | Health endpoint, PostgreSQL, Caddy, admin console, realms |
| wordpress-docker | ✅ | Front page, MariaDB, Caddy, wp-admin, REST API |
| searxng-docker | ✅ | Healthz, Valkey cache, Caddy, search endpoint |
| signoz-docker | ✅ | Health, ClickHouse, OTel Gateway, Zookeeper, UI via Caddy |
| openclaw-docker | ✅ | Container health, Caddy, gateway endpoint |
| sandbox-docker | ✅ | API docs, Caddy, API via Caddy |

## Future Enhancements

- [ ] Performance benchmarks (response time <2s)
- [ ] Security checks (no exposed ports, firewall rules)
- [ ] Monitoring integration (send results to SigNoz)
- [ ] Incident logging (track failures for pattern detection)
