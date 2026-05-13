# GitHub Runner Debug Journal

**Date**: 2026-04-23  
**Issue**: `auto-pr-to-main.yml` workflow failing with `Error: Input required and not supplied: app-id`  
**Status**: Escalated to Roman Di Domizio for official fix  

---

## Timeline

| Time | Event |
|------|-------|
| 2026-04-21 | Engineer set up `auto-pr-to-main.yml` workflow |
| 2026-04-22 | Workflow failing for ~20 hours |
| 2026-04-23 | User escalated — Copilot AI brought in to diagnose |
| 2026-04-23 | Root cause identified: missing GitHub App credentials (`APP_ID`, `APP_PRIVATE_KEY`) |
| 2026-04-23 | Escalated to Roman for official fix and documentation |

---

## Error Message

```text
Error: Input required and not supplied: app-id
    at Object.<anonymous> (/home/runner/work/_actions/actions/create-github-app-token/d72941d797fd3113feb6b93fd0dec494b13a2547/dist/main.cjs:42555:9)
```

**Source**: `actions/create-github-app-token@v1` step in `create-pr` job

---

## Root Cause

The `create-github-app-token` action requires two secrets that were not configured:

- `APP_ID` — GitHub App ID
- `APP_PRIVATE_KEY` — GitHub App private key (.pem file content)

---

## Questions Asked During Debug

1. Was a GitHub App created for this repo?
2. Was the private key generated? If not, where do you generate it?
3. Were the secrets added to **Settings → Secrets and variables → Actions**?
4. What permissions does the GitHub App have? (Needs `Contents: read`, `Pull requests: write`)

---

## What Was Created While Debugging

> **Note**: These files were created as a starting point during debugging. Roman is doing the official fix and will document the proper workflow. These are for reference only.

### Files Created

| File | Purpose |
|------|---------|
| `docs/PRECOMMIT.md` | Pre-commit hooks installation and CI/CD integration docs |
| `.github/workflows/validation.yml` | Validation workflow (pre-commit + lint + security + k8s + compliance + versioning) |
| `.markdownlint.json` | Markdown lint configuration |

### Files Already Present

| File | Purpose |
|------|---------|
| `.pre-commit-config.yaml` | Pre-commit hooks (Gitleaks, yamllint, shellcheck, Helm lint, Terraform, etc.) |
| `.yamllint.yml` | YAML lint configuration |
| `.gitleaks.toml` | Gitleaks configuration |
| `.github/workflows/auto-pr-to-main.yml` | Auto-PR workflow (the one failing) |
| `.github/CI_CD_WORKFLOWS.md` | CI/CD workflow reference documentation |

---

## Official Fix

**Owner**: Roman Di Domizio  
**Status**: In progress — Roman is documenting the proper workflow

Refer to Roman's official documentation for the complete fix and workflow.

---

## Related Documentation

- [PRECOMMIT.md](PRECOMMIT.md) — Pre-commit and CI/CD docs (debugging version)
- [.pre-commit-config.yaml](../.pre-commit-config.yaml) — Pre-commit hooks
- [.github/CI_CD_WORKFLOWS.md](../.github/CI_CD_WORKFLOWS.md) — CI/CD reference
- [.github/workflows/auto-pr-to-main.yml](../.github/workflows/auto-pr-to-main.yml) — Failing workflow
- [.github/workflows/validation.yml](../.github/workflows/validation.yml) — Validation workflow (reference)

---

**Last Updated**: 2026-04-23
