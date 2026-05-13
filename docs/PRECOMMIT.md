# Pre-Commit Hooks & CI/CD Validation

**Purpose**: Document the pre-commit installation process, CI/CD integration, and branch protection requirements for WeOwn AI Infrastructure.

---

## Pre-Commit Hooks (Local)

### Installation

```bash
# Install pre-commit globally
pip install pre-commit

# Navigate to repo and install hooks
cd /path/to/ai
pre-commit install

# Run manually (all files)
pre-commit run --all-files

# Run on specific files
pre-commit run --files "path/to/file.yaml"
```

### Configuration

The pre-commit configuration is in [`.pre-commit-config.yaml`](.pre-commit-config.yaml):

```yaml
# Install: pip install pre-commit && pre-commit install
# Run manually: pre-commit run --all-files
# https://pre-commit.com/
```

### Available Hooks

| Hook | Purpose | Notes |
|------|---------|-------|
| **Gitleaks** | Secret detection | Scans staged changes |
| **yamllint** | YAML linting | Excludes Jinja templates |
| **shellcheck** | Shell script linting | Severity: warning |
| **Helm Lint** | Validate Helm charts | Runs on all `*/helm/Chart.yaml` |
| **Terraform fmt/validate** | IaC validation | Excludes Jinja templates |
| **pre-commit-hooks** | Trailing whitespace, EOF, YAML, large files, merge conflicts, private keys | Various |
| **markdownlint** | Markdown linting | MD013, MD033, MD041 disabled |

### Troubleshooting

**Hook not running?**

```bash
# Reinstall hooks
pre-commit uninstall && pre-commit install

# Update hook versions
pre-commit autoupdate

# Skip all hooks (emergency)
git commit --no-verify -m "emergency commit"
```

**Gitleaks false positive?**
Add to `.gitleaks.toml` or use `--allowlist` in config.

---

## CI/CD Validation (GitHub Actions)

### Required Workflows

#### 1. Validation Workflow (`.github/workflows/validation.yml`)

Runs pre-commit checks plus additional CI/CD validations on every PR and push to main/maintenance.

**Jobs:**

- **Lint** — yamllint, helm lint, shellcheck
- **Security** — Gitleaks, Trivy config scan
- **Kubernetes** — Helm template, kubectl dry-run
- **Compliance** — SOC2/ISO 42001 checks
- **Documentation** — Required files, markdownlint, version consistency
- **Versioning** — WeOwnVer format validation

#### 2. Auto-PR Workflow (`.github/workflows/auto-pr-to-main.yml`)

Automatically creates PRs from feature/fix/docs branches to main. Requires GitHub App authentication.

---

## Branch Protection Rules

### Required Settings for `main` Branch

1. **Require pull request before merging**
   - Require at least 1 approval
   - Dismiss stale reviews

2. **Require status checks to pass before merging**
   Required checks:
   - `lint`
   - `security`
   - `kubernetes`
   - `compliance`
   - `documentation`
   - `versioning`

3. **Require branches to be up to date before merging** (recommended)

4. **Do not allow bypassing the above settings** — even for admins

### How to Configure

1. Go to **Settings → Branches → Branch protection rules**
2. Click **Add rule**
3. Set **Branch name pattern**: `main`
4. Check:
   - ✅ Require a pull request before merging
   - ✅ Require approvals (set to 1+)
   - ✅ Require status checks to pass before merging
   - ✅ Require branches to be up to date before merging
   - ✅ Do not allow bypassing the above settings

---

## Credentials Reference

### GitHub App (for auto-PR workflow)

| Secret | Description |
|--------|-------------|
| `APP_ID` | GitHub App ID (found in GitHub App settings) |
| `APP_PRIVATE_KEY` | Private key (.pem file content) |

**To create a GitHub App:**

1. Go to **Settings → Developer settings → GitHub Apps**
2. Click **New GitHub App**
3. Set:
   - **Name**: WeOwn AI CI (or similar)
   - **Homepage URL**: Your repo URL
   - **Permissions**: Repository permissions → Contents: read, Pull requests: write
4. Generate private key under **Private keys**

### Adding Secrets to GitHub

1. Go to **Settings → Secrets and variables → Actions**
2. Click **New repository secret**
3. Add `APP_ID` and `APP_PRIVATE_KEY`

---

## Common Errors

### "Input required and not supplied: app-id"

The `auto-pr-to-main.yml` workflow is missing GitHub App secrets. See [Credentials Reference](#github-app-for-auto-pr-workflow).

### Pre-commit hooks pass locally but fail in CI

Ensure the CI runner has pre-commit installed:

```yaml
- name: Install pre-commit
  run: pip install pre-commit
```

### Validation workflow not running on PRs

Check that the workflow triggers are configured:

```yaml
on:
  pull_request:
    branches: [main, maintenance]
  push:
    branches: [main, maintenance]
```

### Status checks not appearing in PR

1. Go to **Settings → Branches → Branch protection rules**
2. Edit the `main` rule
3. Under **Status checks**, add the required job names (lint, security, kubernetes, compliance, documentation, versioning)

---

## Quick Reference

```bash
# Local pre-commit commands
pre-commit install              # Install hooks
pre-commit run --all-files     # Run all hooks
pre-commit run -a              # Run on all files (including staged)
pre-commit autoupdate          # Update hook versions

# Check hook status
pre-commit run --show-diff-on-failure
```

---

**Last Updated**: 2026-04-23
**Maintained By**: WeOwn AI Infrastructure Team
