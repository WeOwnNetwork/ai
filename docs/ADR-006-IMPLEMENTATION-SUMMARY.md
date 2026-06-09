# ADR-006 Implementation Summary

**Branch:** `feature/mot-adr006-in-container-infisical`  
**Date:** 2026-06-08  
**Status:** Complete — all 7 templates updated  
**Commits:** 9 commits (1 docs + 7 templates + 1 README batch)

---

## What Was Implemented

Adopted Nik's ADR-006 standard across all 7 docker templates, moving secret resolution from **host-side wrap** to **in-container entrypoint**. This enables:

- **Bounce-to-refresh:** `docker restart` re-fetches secrets from Infisical (no redeploy needed)
- **Consumer-side auto-rotation:** Rotate a secret in Infisical → bounce container → new value loaded
- **Better security:** Secrets not in compose `environment:` block → not visible in `docker inspect`
- **K8s forward-compatibility:** Same conceptual pattern maps to Infisical Secrets Operator

---

## Templates Updated

| Template | Containers | Secrets | Multi-Container Pattern |
|----------|-----------|---------|------------------------|
| **anythingllm-docker** | 1 (anythingllm) | `ANYTHINGLLM_IMAGE`, `OPENROUTER_API_KEY`, `JWT_SECRET`, `ADMIN_EMAIL` | Single container (cleanest case) |
| **searxng-docker** | 1 (searxng) + valkey | `SEARXNG_SECRET` | Single app (valkey has no secrets) |
| **sandbox-docker** | 1 (sandbox) | `JWT_PUBLIC_KEY`, `GITHUB_TOKEN`, `PROXY_SERVER` | Single container |
| **openclaw-docker** | 1 (openclaw) | `OPENCLAW_GATEWAY_TOKEN`, `OPENROUTER_API_KEY`, `SIGNOZ_INGESTION_KEY`, `PROXY_SERVER` | Single container |
| **wordpress-docker** | 3 (db + wordpress + caddy) | MariaDB: `MYSQL_DATABASE`, `MYSQL_USER`, `MYSQL_PASSWORD`, `MYSQL_ROOT_PASSWORD`<br>WordPress: `WORDPRESS_DB_NAME`, `WORDPRESS_DB_USER`, `WORDPRESS_DB_PASSWORD`, `DOMAIN` | **Secret duplication:** `MYSQL_*` → `WORDPRESS_DB_*` (same values, different names) |
| **keycloak-docker** | 3 (db + keycloak + caddy) | PostgreSQL: `POSTGRES_DB`, `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_ROOT_PASSWORD`<br>Keycloak: `KC_DB_USERNAME`, `KC_DB_PASSWORD`, `KEYCLOAK_ADMIN`, `KEYCLOAK_ADMIN_PASSWORD` | **Secret duplication:** `POSTGRES_USER` → `KC_DB_USERNAME`, `POSTGRES_PASSWORD` → `KC_DB_PASSWORD` |
| **signoz-docker** | 5 (zookeeper + clickhouse + schema-migrator + signoz + otel-collector) | `CLICKHOUSE_PASSWORD` (shared by 4 services), `SIGNOZ_ADMIN_EMAIL`, `SIGNOZ_ADMIN_PASSWORD` | **Shared secret:** `CLICKHOUSE_PASSWORD` used by all 4 services |

---

## Per-Template Changes

### Compose Files (`template/docker/compose.prod.yaml.jinja`)

**Before (host-side wrap):**

```yaml
services:
  app:
    image: myapp:latest
    environment:
      SECRET_KEY: ${SECRET_KEY:?not injected}
```

**After (ADR-006 in-container entrypoint):**

```yaml
services:
  app:
    image: myapp:latest
    entrypoint: ["/usr/bin/infisical", "run", "--projectId={{ infisical_project_id }}", "--env={{ infisical_env }}", "--"]
    environment:
      # Non-secret config only
      APP_MODE: production
      # Secrets fetched by entrypoint, NOT listed here
    volumes:
      - /usr/bin/infisical:/usr/bin/infisical:ro
      - /opt/{{ project_name }}/.infisical-auth.env.container:/.infisical-auth.env:ro
```

### Ansible Playbooks (`template/ansible/deploy.yml.jinja`)

**Before (host-side wrap):**

```yaml
- name: Ensure compose stack is running
  shell: |
    source {{ app_dir }}/.infisical-auth.env
    infisical login --method=universal-auth ...
    infisical run --projectId=... -- docker compose up -d
```

**After (ADR-006):**

```yaml
- name: Create container-readable auth file (ADR-006)
  copy:
    src: "{{ app_dir }}/.infisical-auth.env"
    dest: "{{ app_dir }}/.infisical-auth.env.container"
    mode: "0640"
    remote_src: true

- name: Ensure compose stack is running
  shell: |
    cd {{ app_dir }}
    docker compose up -d  # NO infisical run wrapper
```

### READMEs

All 7 template READMEs updated to document:

- In-container secret fetch via `infisical run` entrypoint
- Bounce-to-refresh (`docker restart` re-fetches secrets)
- Zero secrets in `docker inspect`
- Consumer-side auto-rotation capability
- Multi-container secret duplication (where applicable)

---

## Multi-Container Secret Duplication

For stacks where multiple containers expect secrets under different env var names:

**WordPress example:**

- MariaDB expects: `MYSQL_DATABASE`, `MYSQL_USER`, `MYSQL_PASSWORD`
- WordPress expects: `WORDPRESS_DB_NAME`, `WORDPRESS_DB_USER`, `WORDPRESS_DB_PASSWORD`

**Solution:** Store secrets in Infisical under **both names** (same values, different keys):

- `MYSQL_DATABASE` = `wordpress_db`
- `WORDPRESS_DB_NAME` = `wordpress_db` (same value)
- `MYSQL_USER` = `wp_user`
- `WORDPRESS_DB_USER` = `wp_user` (same value)
- etc.

**Why this works:**

- Each container uses `infisical run` entrypoint
- `infisical run` injects ALL secrets from the project into the container's process env
- MariaDB reads `MYSQL_*` vars, ignores `WORDPRESS_DB_*` vars
- WordPress reads `WORDPRESS_DB_*` vars, ignores `MYSQL_*` vars
- No wrapper scripts needed, compose files stay clean

**Tradeoff:** When rotating a shared secret (e.g., DB password), you update it in Infisical under multiple names. This is a 10-second copy-paste in the Infisical dashboard, and the `deploy-new-site.sh` script can automate it at creation time.

---

## Compliance Mapping

| Control | Addressed by |
|---------|--------------|
| NIST CSF 2.0 PR.AC-4 (least privilege) | Per-workload, per-project Machine Identity; no shared identity |
| NIST CSF 2.0 PR.DS-1 (data protection) | Secrets out of committed config and `docker inspect` |
| CIS Controls v8 5.3 (credential rotation) | In-container fetch gives rotation a consumer-side trigger (bounce) |
| ISO/IEC 27001:2022 A.5.17 (authentication information) | No app secrets in config files; Infisical-backed at runtime |
| FedArch PRJ-024 (Secrets Management) | Exceeds PRJ-024's init container approach; aligns with runtime injection standard |
| FedArch PRJ-032 (OpenTofu IaC) | Complements IaC pattern with runtime secret delivery |

---

## What's NOT in This Branch

**Live sites not updated:**

- `anythingllm-docker/sites/ai.weown.agency/`
- `anythingllm-docker/sites/s004.ccc.bot/`
- `keycloak-docker/sites/sso.weown.dev/`
- `wordpress-docker/sites/burnedout-xyz/`
- `wordpress-docker/sites/ptoken-agency/`
- `wordpress-docker/sites/stage-burnedout-xyz/`
- `openclaw-docker/sites/claw-weown-tools/`

**Why:** Live sites are rendered from templates. When the templates merge to main, the sites can be re-rendered to pick up ADR-006 changes. Alternatively, they can be manually updated by copying the template changes into the site directories.

**Scripts not updated:**

- `scripts/deploy-new-site.sh` — currently generates secrets with names like `DB_PASSWORD`, `DB_USER`. Should be updated to generate `POSTGRES_PASSWORD`, `POSTGRES_USER`, `KC_DB_PASSWORD`, `KC_DB_USERNAME`, `MYSQL_PASSWORD`, `MYSQL_USER`, `WORDPRESS_DB_PASSWORD`, `WORDPRESS_DB_USER` (duplicated as needed).

**Why:** This is a separate concern from the template updates. The script can be updated in a follow-up PR once the templates are merged.

---

## Testing Recommendations

Before merging to main:

1. **Render a test site** from each template using `copier`
2. **Verify compose files** have correct `entrypoint:` and bind-mounts
3. **Verify ansible playbooks** create `.infisical-auth.env.container` and drop `infisical run` wrapper
4. **Test bounce-to-refresh:**
   - Deploy a site
   - Change a secret in Infisical
   - Run `docker restart <container>`
   - Verify the container picks up the new value (check logs or app behavior)
5. **Verify `docker inspect`** does NOT show secrets in `Config.Env`

---

## Next Steps

1. **Review this branch** (9 commits, all templates + READMEs)
2. **Test rendering** from templates
3. **Update `deploy-new-site.sh`** to generate duplicated secret names (follow-up PR)
4. **Merge to main** after review + testing
5. **Re-render live sites** from updated templates (or manually update site directories)

---

## Related Documents

- **ADR-006:** `.github/ADR-006-in-container-infisical-injection.md` (on Nik's branch `docs/nik-adr006-infisical-injection`)
- **Bootstrap pattern:** `docs/INFRA_BOOTSTRAP_PATTERN.md` (Layer 1 + Layer 2 + Path C)
- **FedArch secrets:** `CCCbotNet/fedarch/_PROJECTS_/PRJ-024_Secrets-Management-Infisical.md`
- **FedArch IaC:** `CCCbotNet/fedarch/_PROJECTS_/PRJ-032_OpenTofu-IaC.md`
- **Work log:** `WORK_LOG.md` (Phase 2.5 section)

---

**Implementation complete.** All 7 templates now follow ADR-006 standard with in-container Infisical injection, bounce-to-refresh capability, and multi-container secret duplication where needed.
