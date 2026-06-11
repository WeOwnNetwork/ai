# WeOwn `ai` — AGENTS.md (Canonical Agent Rules)

> #WeOwnVer: v4.1.2.1 · Status: ACTIVE · Scope: every AI coding agent, every session, the whole repo

This is the canonical, tool-neutral rule set for AI agents working in this repo —
Codex, Cursor, Windsurf, Cline, Aider, Jules, Gemini CLI, GitHub Copilot agent mode,
Zed, Claude Code, and anything newer that reads `AGENTS.md`.

How each tool gets here:

| Tool | Auto-loads | Route |
| --- | --- | --- |
| Codex · Cursor · Windsurf · Cline · Aider · Jules · Copilot agent mode | `AGENTS.md` | this file, natively |
| Zed | `.rules` (first-match wins) | `.rules` summarizes and points here |
| Claude Code | `CLAUDE.md` | points here |
| Gemini CLI | `GEMINI.md` | pointer stub |
| Legacy Cursor / Windsurf / Cline | `.cursorrules` / `.windsurfrules` / `.clinerules` | pointer stubs (byte-identical) |
| GitHub Copilot code review | `.github/copilot-instructions.md` | separate file: the 780+ line PR-review / compliance checklist |

On conflict about **agent behavior with secrets**, this file wins. On conflict about
**PR-review depth and compliance checklists**, `.github/copilot-instructions.md` wins.
Keep this file and `.rules` in sync when editing either.

---

## ⛔ Non-negotiables

1. **THIS REPO IS PUBLIC** on github.com. Never commit secrets, API keys, tokens,
   passwords, real IPs (public LB IPs included), DOKS cluster names/IDs/UUIDs,
   node-pool names, kubeconfig context names, DO Spaces bucket names, internal DNS,
   PV IDs, or PII. Use placeholders: `<CLUSTER_NAME>`, `<INGRESS_LB_IP>`,
   RFC 5737 IPs (`203.0.113.x`), RFC 2606 domains (`example.com`). History is
   forever — a value committed once needs `git filter-repo` **and** rotation, not
   just removal from the diff. CI/gitleaks catches secret *patterns*, not topology;
   you and human review are the gate.
2. **Secrets never on disk, never in agent context** — full standard in the next
   section.
3. **Branch naming (CI-enforced):** `<type>/<dev>-<description>` matching
   `^(feature|fix|docs|hotfix)/[a-z0-9]{2,}-[a-z0-9]{3,}(-[a-z0-9]+)*$`.
   `<dev>` is your human handle (`nik`, `dilonne`, `shahid`, `mohammed`) — not a
   project code.
4. **#OnlyHumanApproves (R-011):** AI proposes, the human decides. Never push,
   merge, `tofu apply`, deploy, delete, or touch production without explicit human
   approval. During migrations, never modify the live/old environment before soak.
5. **Every PR carries:** a real description (Summary · Decisions · Test plan ·
   Not-in-scope), a `#WeOwnVer` stamp on new docs, a root `CHANGELOG.md`
   `[Unreleased]` entry for repo-level changes, and every review comment addressed
   or deferred with a written reason.

## 🔐 Secrets-hygiene standard

### S1. The agent never reads or extracts secrets — ever

You MUST NOT read, display, echo, or otherwise pull into your context any secret,
token, password, API key, or credential, from any source:

- `.env` files (local or remote) — `cat`, file-read tools, editor buffers
- process env: `env`, `printenv`, `ps eww`, `/proc/<pid>/environ`
- containers/clusters: `docker exec ... env`, `docker inspect`,
  `kubectl get secret -o yaml`
- secret managers: Infisical / Vault / OpenBao CLI or API reads,
  `security find-generic-password`, `keyring`
- SSH sessions that would print env vars; shell history files; local artifacts
  like `*.log` dumps and `.terraform/terraform.tfstate`

**Why:** anything that enters agent context is sent to a model API and persists in
transcripts, prompt caches, and session archives. A secret read on turn 3 leaks on
every later turn. It cannot be un-read.

**Instead — Secure Handoff:** write a self-contained script with `read -rs`
prompts and hand it to the human to run. The secret stays in their shell; they
report the outcome ("done" / "failed at step 4"); you proceed on the outcome. If a
handoff genuinely cannot work, stop and explain why — never improvise a path that
routes the value through your context.

### S2. No credentials hardcoded in repo files

Applies to every file type — `.sh`, `.py`, `.js`/`.ts`, `.go`, `.yaml`, `.tf`,
`.json`, `.toml`, Markdown examples, "throwaway" test scripts. "It's just for
testing" or "the key is already revoked" is how long-lived leaks are born.

Source credentials only from:

1. **Infisical at runtime** (the project standard — mandatory; see `CLAUDE.md` and
   `.github/copilot-instructions.md` §3.10):
   - Kubernetes → `InfisicalSecret` CRD
   - Docker Compose → `infisical run -- docker compose up -d` (droplets re-read
     Infisical only at deploy time — see S4 step 4)
   - GitHub Actions → Infisical Secret Sync → `${{ secrets.* }}`
   - OpenTofu / Ansible → Machine Identity variables only; app secrets fetched at
     runtime (`itofu.sh` pattern)
2. **Process env with a fail-loud, tells-you-where error:**

   ```bash
   #!/usr/bin/env bash
   set -euo pipefail
   : "${FOO_API_TOKEN:?Set FOO_API_TOKEN (Infisical -> project <name> -> env prod -> /path/FOO_API_TOKEN)}"
   ```

   ```python
   import os, sys
   TOKEN = os.environ.get("FOO_API_TOKEN", "")
   if not TOKEN:
       sys.exit("Set FOO_API_TOKEN (Infisical -> project <name> -> env prod -> /path)")
   ```

3. **Interactive prompt** for one-shot admin scripts (rotation, breakglass,
   migrations):

   ```bash
   read -rs "TOKEN?Paste TOKEN: " 2>/dev/null \
     || read -rsp "Paste TOKEN: " TOKEN
   echo
   trap 'unset TOKEN 2>/dev/null || true' EXIT
   # forward into a remote container with NO argv exposure anywhere (local,
   # remote host, or container) - stdin flows printf -> ssh -> docker exec -i:
   printf '%s\n' "$TOKEN" \
     | ssh "$HOST" 'docker exec -i ctr sh -c "read -r TOKEN; export TOKEN; exec cmd"'
   ```

Never pass secrets on argv (`cmd --token=...`, `-e VAR=value`) — argv leaks into
`ps`, shell history, and SSH session logs. Commit `.env.example` with placeholders
only.

### S3. Two scanning layers — both pinned to the same gitleaks version

Already running in this repo. Keep the two pins in lock-step — if you bump one,
bump the other in the same PR:

| Layer | Where | Pin |
| --- | --- | --- |
| pre-commit (staged files) | `.pre-commit-config.yaml` gitleaks hook | v8.18.4 |
| CI (every push/PR) | `.github/workflows/validation.yml` "Secret Detection (Gitleaks)" | v8.18.4 |

Shared config: `.gitleaks.toml` (default ruleset + allowlist). Run
`pre-commit install` once per fresh checkout. Note: both layers scan the working
tree / staged files, **not** git history — a secret that ever landed in a commit is
compromised even after removal (rotate it and purge with `git filter-repo`, per
`.github/copilot-instructions.md` §3.0).

### S4. Found a hardcoded secret? The rotation flow, in order

Order matters — do not deviate:

1. **Verify it is live** (probe the API it belongs to; use a real-browser
   User-Agent if the endpoint sits behind Cloudflare). Dead = no rotation, just
   scrub.
2. **Map every runtime consumer** and plan how each one gets the new value.
3. **Mint the replacement BEFORE revoking** the old one — the old key's last
   legitimate act is authenticating the mint of its successor.
4. **Update every consumer**: push to Infisical, then redeploy. Droplet apps read
   Infisical only at `infisical run -- docker compose up` (run `deploy.sh`;
   `docker compose restart` reuses the old env). Kubernetes `InfisicalSecret`
   reloads live.
5. **Verify end-to-end** while the old key still works as fallback.
6. **THEN revoke** the old credential.
7. **Scrub the repo** in one auditable commit (env-var pattern with a
   fetch-from-where error string).
8. **Document**: commit message + `.github/INCIDENT_RESPONSE.md` entry (+
   CHANGELOG). For public-repo leaks also purge history (`git filter-repo`).

If steps 4–6 need an admin token you do not have: **stop and say so**. Do not
harvest it from a remote `.env` — write the script with `read -rs` prompts and let
the human run it (S1).

**Multi-orphan check:** a prior rotation that crashed mid-flow may have minted a
replacement that was never wired up. Fingerprint: a recent key whose creation /
`last_used_on` matches the minute the failed rotation ran and whose description
matches the rotation template. Rotation scripts should accept a list of stale key
IDs to delete in one pass and treat DELETE → HTTP 404 as success so re-runs
converge.

### S5. Shell patterns that have actually bitten this platform

#### SSH + heredoc variable expansion

Do not splice local values into a remote single-quoted body with `'"$VAR"'` —
under remote `set -u`, any unrelated unset variable downstream errors with the
wrong variable name and you will chase the wrong bug. Pass locals as positional
args to `bash -s`; stream secrets via stdin:

```bash
printf '%s\n' "$SECRET" | ssh "$HOST" bash -s "$LOCAL_PATH" <<'REMOTE'
set -euo pipefail
LOCAL_PATH="$1"
read -r SECRET
export SECRET            # env, not argv (S2) - do_thing reads $SECRET itself
do_thing "$LOCAL_PATH"
REMOTE
```

#### Unicode immediately after `$VAR` in `.sh` files

Never place a non-ASCII character (the usual landmine is `…` U+2026) directly
after a `$VAR` reference — older bash builds fold the first UTF-8 byte into the
variable name and die under `set -u` with a misleading name. Use ASCII `...` or
insert an ASCII separator. (Related: cloud-init user-data must be pure ASCII —
see CHANGELOG 2026-06-02.)

#### Terraform `templatefile()` and `$$`

In cloud-init templates rendered by `templatefile()`, escape **only** a literal
`${...}` as `$${...}` (covers `${VAR:-default}` and Infisical-injected
`$${SECRET}`). A plain `$VAR` or `$(...)` passes through unchanged. **Never write
`$$VAR` or `$$(...)`** — Terraform leaves the `$$` literal and bash expands it as
its PID, silently corrupting the script. This exact bug broke Layer-2 secret
rotation fleet-wide (CHANGELOG 2026-06-02).

## ✅ How we work

- 8-step loop: understand → investigate the codebase → plan → implement in small
  testable steps → debug the root cause (not the symptom) → test after every
  change → iterate → verify against the original ask.
- Search before declaring; prove before verifying (GUIDE-015). Never assert a
  file/fact exists without checking; never report "done" without running the check
  that proves it. Zero fabrication.
- Match the existing toolchain — copier templates for `*-docker/` (clone
  `keycloak-docker/`; cloud-init key is `runcmd:` singular), Infisical for
  secrets, OpenTofu (`tofu`) for IaC, the project scripts. Never reinvent.
- Validate before you commit: `bash -n` (shell), `yamllint`, `tofu validate`,
  `pre-commit run --all-files`.
- Change only what the task needs. No drive-by refactors; no comments/docstrings/
  types on untouched code.
- Identity (#FedArch): accounts are `u-<ccc>_user` (DEFAULT) / `a-<ccc>_dev`
  (ADMIN). On a shared AnythingLLM instance, self-identify in the first message
  (BP-065).

## 📚 Depth lives in

- Review / compliance checklist → `.github/copilot-instructions.md` (§3.0
  redaction, §3.10 secrets)
- Project patterns, branch naming, versioning → `CLAUDE.md`,
  `docs/VERSIONING_WEOWNVER.md`
- Incident / rotation runbook → `.github/INCIDENT_RESPONSE.md`,
  `scripts/rotate-do-spaces-keys.sh`, `scripts/verify-infisical-secrets.sh`
- Deploy / migration reference → `anythingllm-docker/DEPLOYMENT_GUIDE.md`
- Zed entry file → `.rules` (summarizes this file; keep in sync)
