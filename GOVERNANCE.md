# Governance & Working Agreements

**Last Updated:** 2026-06-08  
**Status:** Active

---

## Working Principles

### Quality Gate Before Production Push

**Established:** 2026-06-08  
**Context:** We pushed ADR-006 implementation to prod without adequate testing. Reviewers found critical bugs (entrypoint auth, Keycloak DB name). This wastes reviewer time and damages credibility.

**Principle:**
Before pushing any work to prod/upstream:

1. **Render test sites from templates** (not just static analysis)
   - Use `copier` to render at least one test site
   - Inspect rendered compose files, ansible playbooks
   - Verify bind-mounts, entrypoints, secret references

2. **Verify syntax**
   - Run `docker-compose config` on rendered compose files
   - Run `ansible-playbook --syntax-check` on playbooks
   - Check YAML/Jinja syntax

3. **Test critical paths**
   - Entrypoint authentication (will it actually authenticate?)
   - Secret injection (will secrets be available to the app?)
   - Healthchecks (will they pass?)
   - Multi-container secret duplication (will apps read the right vars?)

4. **User reviews and approves**
   - Peter reviews the work before push
   - No pushing to prod without explicit approval

5. **Only then push to prod**
   - After all verification passes
   - After user gives explicit go-ahead

**Rationale:**

- Reviewers should find clean, tested work
- We catch bugs before they do
- Respects reviewer time
- Maintains credibility

**Applies to:**

- All template changes
- All ansible playbook changes
- All compose file changes
- All documentation that affects deployment

---

## Decisions & Rationale

### Secret Duplication Strategy (ADR-006 Implementation)

**Date:** 2026-06-08  
**Decision:** Duplicate secrets in Infisical under multiple names (e.g., `MYSQL_PASSWORD` and `WORDPRESS_DB_PASSWORD` hold the same value)

**Alternatives Considered:**

1. **Wrapper entrypoint scripts** - Create scripts that map env vars
   - Rejected: Adds complexity, harder to maintain
2. **Single secret with multiple references** - Use one secret, reference it multiple ways
   - Rejected: Infisical doesn't support this pattern
3. **Secret duplication** - Store same value under multiple names
   - Accepted: Simple, clean compose files, no wrapper scripts

**Trade-offs:**

- ✅ Clean compose files (no wrapper scripts)
- ✅ Each app sees env vars it expects
- ❌ When rotating a secret, must update multiple names in Infisical
- ❌ Slightly more secrets to manage

**Mitigation:**

- Document which secrets are duplicated
- `deploy-new-site.sh` can automate duplication at creation time
- 10-second copy-paste in Infisical dashboard when rotating

### Deferred Live Site Updates

**Date:** 2026-06-08  
**Decision:** Do not update live sites in this PR; defer to follow-up work

**Rationale:**

- Live sites are rendered from templates
- When templates merge to main, sites can be re-rendered
- Alternatively, manually copy template changes to site directories
- Keeps this PR focused on template changes only

**Trade-offs:**

- ✅ Smaller, focused PR
- ✅ Easier to review
- ❌ Live sites won't have ADR-006 until re-rendered
- ❌ Requires follow-up work after merge

---

## Chores & Deferred Work

### Live Sites Need Re-rendering

**Priority:** Medium  
**Effort:** ~30 minutes  
**When:** After PR #68 merges to main

**Sites to update:**

- `anythingllm-docker/sites/ai.weown.agency/`
- `anythingllm-docker/sites/s004.ccc.bot/`
- `keycloak-docker/sites/sso.weown.dev/`
- `wordpress-docker/sites/burnedout-xyz/`
- `wordpress-docker/sites/ptoken-agency/`
- `wordpress-docker/sites/stage-burnedout-xyz/`
- `openclaw-docker/sites/claw-weown-tools/`

**Approach:**

1. Re-render each site from updated templates using `copier`
2. Or manually copy template changes to site directories
3. Test each site (render, validate syntax)
4. Create follow-up PR with site updates

### deploy-new-site.sh Needs Secret Name Updates

**Priority:** Low  
**Effort:** ~1 hour  
**When:** After PR #68 merges to main

**Current behavior:**

- Generates secrets with names like `DB_PASSWORD`, `DB_USER`

**Required behavior:**

- Generate duplicated secret names:
  - WordPress: `MYSQL_PASSWORD` + `WORDPRESS_DB_PASSWORD`
  - Keycloak: `POSTGRES_PASSWORD` + `KC_DB_PASSWORD`
  - etc.

**Approach:**

1. Update script to generate duplicated names
2. Test with each template
3. Create follow-up PR

---

## Conditionals & Decision Trees

### If Reviewer Finds Bugs

**Condition:** Reviewer comments on PR with bug report  
**Action:**

1. Fix the bug immediately
2. Test the fix (render, validate, test critical path)
3. Push fix to branch
4. Comment on PR explaining the fix
5. Request re-review

**Do NOT:**

- Argue with reviewer
- Push untested fixes
- Ignore the bug

### If Template Changes

**Condition:** Template files are modified (compose, ansible, etc.)  
**Action:**

1. Render at least one test site from the template
2. Verify rendered output is correct
3. Test critical paths (entrypoint, secrets, healthchecks)
4. Only then push to prod

**Do NOT:**

- Push without rendering
- Assume it works because syntax is valid
- Skip testing "because it's a small change"

### If Multi-Container Stack

**Condition:** Template has multiple containers that need secrets  
**Action:**

1. Identify which containers need which secrets
2. Determine if secret duplication is needed (different env var names)
3. Document the duplication strategy
4. Test that each container reads the right vars
5. Verify no conflicts (container A doesn't read container B's vars)

**Do NOT:**

- Assume all containers can share the same secret names
- Skip testing multi-container interactions
- Forget to document the duplication

---

## Lessons Learned

### Lesson 1: Static Analysis Is Not Enough (2026-06-08)

**What happened:**

- Implemented ADR-006 across all 7 templates
- Did static analysis (syntax, logic review)
- Pushed to prod
- Reviewers found critical bugs (entrypoint auth, Keycloak DB name)

**Root cause:**

- Didn't render test sites
- Didn't test entrypoint authentication
- Didn't verify Keycloak's env var requirements
- Assumed it would work because syntax was valid

**Lesson:**

- Static analysis catches syntax errors, not logic errors
- Must render and test before pushing
- Reviewers should find clean work, not bugs

**Applied:**

- Created "Quality Gate Before Production Push" principle
- Will render test sites for all future template changes

---

## Future Improvements

### Automated Testing Pipeline

**Goal:** Automate the Quality Gate checks  
**Priority:** Low (manual process works for now)  
**Effort:** ~1 week

**What it would do:**

1. Render test sites from templates (CI job)
2. Run `docker-compose config` on rendered files
3. Run `ansible-playbook --syntax-check`
4. Optionally: spin up test containers and verify they start
5. Report results in PR

**Benefits:**

- Catches bugs automatically
- Faster feedback loop
- Reduces manual testing burden

**Drawbacks:**

- Requires CI infrastructure
- Complex to set up (rendering, container orchestration)
- Might be overkill for current scale

**Decision:** Defer until manual testing becomes a bottleneck
