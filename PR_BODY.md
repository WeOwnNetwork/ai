## Problem

Operators currently re-type `INFISICAL_PROJECT_ID` across 4 scripts (deploy.sh, backup.sh, restore.sh, itofu.sh) for every invocation. This creates friction and opportunities for typos.

## Solution

Add a `site.conf` file to each site that stores non-secret identifiers (`INFISICAL_PROJECT_ID`, `INFISICAL_ENV`). Scripts read this file automatically via a safe config reader that only accepts `UPPER_CASE=value` lines (prevents arbitrary code execution).

## Changes

### Template (for new sites)

- **`template/site.conf.jinja`** — renders `INFISICAL_PROJECT_ID` and `INFISICAL_ENV` from copier values
- **`template/scripts/lib.sh.jinja`** — safe config reader (`load_site_conf()`) with strict allowlist parser
- **Updated all 4 operator scripts** — deploy.sh, backup.sh, restore.sh, itofu.sh now source site.conf
- **Removed `template/terraform/init.sh.jinja`** — dead code (itofu.sh already handles this via Infisical)

### Live sites (s004.ccc.bot, ai.weown.agency)

- **Added `site.conf`** — `INFISICAL_ENV=prod`, `INFISICAL_PROJECT_ID` blank (operator fills in)
- **Added `scripts/lib.sh`** — safe config reader
- **Updated deploy.sh, backup.sh, restore.sh** — now read site.conf automatically

### Tooling

- **`answers.yaml.example`** — documented copier answers for repeatable renders
- **`scripts/lint-site-conf.sh`** — rejects secret-shaped keys (SECRET, PASSWORD, TOKEN, KEY, etc.)

### Documentation

- **Updated README.md** — quick-start with both interactive and answers.yaml workflows
- **Updated sites/README.md** — same copier workflow options
- **Updated directory structure** — reflects new files and removed init.sh.jinja

## Security

### What's in site.conf (safe to commit)

- `INFISICAL_PROJECT_ID` — UUID, useless without Machine Identity credentials
- `INFISICAL_ENV` — environment slug (prod/staging/dev)

### What's NOT in site.conf (never commit)

- Secrets (JWT_SECRET, OPENROUTER_API_KEY, etc.) — live in Infisical
- Machine Identity credentials — live on droplet at `/opt/<project>/.infisical-auth.env` (0600 root, rotated by Layer 2)
- WEOWN_TOFU_PROJECT_ID — operator-global, set once in shell profile

### Hardening

- **Safe reader**: `load_site_conf()` only accepts `^[A-Z_][A-Z0-9_]*=.*$` lines (no arbitrary code execution)
- **Env var precedence**: Env vars override site.conf values (flexibility for overrides)
- **Lint check**: `scripts/lint-site-conf.sh` rejects keys matching `(SECRET|PASSWORD|TOKEN|KEY|CREDENTIAL|AUTH|PRIVATE|CERT)`

## Operator Workflow (After)

```bash
# 1. Render site (one-time)
cd anythingllm-docker
cp answers.yaml.example answers.yaml
# edit answers.yaml
copier copy . sites/ai.newsite.com --data-file answers.yaml --trust

# 2. Fill in site.conf (30 seconds)
cd sites/ai.newsite.com
vim site.conf
# INFISICAL_PROJECT_ID=<paste from Infisical UI>

# 3. Deploy (ongoing, no env vars needed!)
./scripts/deploy.sh root@<ip>
./scripts/backup.sh root@<ip>
./scripts/restore.sh root@<ip> <backup-name>
```

## Testing

- ✅ Safe reader tested (accepts UPPER_CASE, rejects lowercase, strips quotes)
- ✅ Lint script tested (passes on valid files, rejects secret-shaped keys)
- ✅ All pre-commit hooks pass (gitleaks, shellcheck, markdownlint, etc.)

## Commits (7 total)

1. `feat(anythingllm-docker): add site.conf template + safe config reader`
2. `feat(anythingllm-docker): wire site.conf into deploy/backup/restore/itofu scripts`
3. `chore(anythingllm-docker): remove unused init.sh.jinja`
4. `feat(anythingllm-docker): add answers.yaml.example + lint-site-conf.sh`
5. `feat(anythingllm-docker): add site.conf to live sites (s004.ccc.bot, ai.weown.agency)`
6. `docs(anythingllm-docker): update README quick-start + directory structure for site.conf`
7. `feat(anythingllm-docker): update live site scripts to use site.conf`

## Follow-up Work (Separate PRs)

- `feat/mot-sandbox-site-conf` — apply same pattern to sandbox-docker
- `feat/mot-openclaw-site-conf` — apply same pattern to openclaw-docker
- Infisical outage runbook (documentation)
- Makefile per site (nice-to-have)

## Files Changed

**Added (8 files):**

- `anythingllm-docker/template/site.conf.jinja`
- `anythingllm-docker/template/scripts/lib.sh.jinja`
- `anythingllm-docker/answers.yaml.example`
- `scripts/lint-site-conf.sh`
- `anythingllm-docker/sites/s004.ccc.bot/site.conf`
- `anythingllm-docker/sites/s004.ccc.bot/scripts/lib.sh`
- `anythingllm-docker/sites/ai.weown.agency/site.conf`
- `anythingllm-docker/sites/ai.weown.agency/scripts/lib.sh`

**Modified (12 files):**

- `anythingllm-docker/template/scripts/deploy.sh.jinja`
- `anythingllm-docker/template/scripts/backup.sh.jinja`
- `anythingllm-docker/template/scripts/restore.sh.jinja`
- `anythingllm-docker/template/terraform/itofu.sh.jinja`
- `anythingllm-docker/README.md`
- `anythingllm-docker/sites/README.md`
- `anythingllm-docker/sites/s004.ccc.bot/scripts/deploy.sh`
- `anythingllm-docker/sites/s004.ccc.bot/scripts/backup.sh`
- `anythingllm-docker/sites/s004.ccc.bot/scripts/restore.sh`
- `anythingllm-docker/sites/ai.weown.agency/scripts/deploy.sh`
- `anythingllm-docker/sites/ai.weown.agency/scripts/backup.sh`
- `anythingllm-docker/sites/ai.weown.agency/scripts/restore.sh`

**Deleted (1 file):**

- `anythingllm-docker/template/terraform/init.sh.jinja`

## Stats

21 files changed, 471 insertions(+), 124 deletions(-)
