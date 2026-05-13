# Contributing to `WeOwnNetwork/ai`

Welcome. This guide covers everything you need to contribute to the WeOwn AI infrastructure repository.

**Version**: v3.4.2.1 (#WeOwnVer — see [`docs/VERSIONING_WEOWNVER.md`](docs/VERSIONING_WEOWNVER.md))
**Last updated**: 2026-05-13 (R12 §4 attribution-fallback fix + R13 header date sync + R19 §4 `Contributors on this branch:` label canonicalization + Copilot R1 §8 force-push fix + contributor/reviewer updates)

---

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [First-Time Developer Setup](#2-first-time-developer-setup)
3. [Commit Signing (REQUIRED)](#3-commit-signing-required)
4. [Branching Model (GitHub Flow) & Naming Convention](#4-branching-model-github-flow--naming-convention)
5. [Commit Message Conventions](#5-commit-message-conventions)
6. [Pull Request Workflow](#6-pull-request-workflow)
7. [Code Review Expectations](#7-code-review-expectations)
8. [Troubleshooting Signed Commits](#8-troubleshooting-signed-commits)
9. [Compliance & Governance References](#9-compliance--governance-references)

---

## 1. Prerequisites

Before your first contribution, ensure you have:

- **GitHub account** added to the `WeOwnNetwork` organization (ask `@ncimino`)
- **2FA enabled** on your GitHub account (required by org policy)
- **Git 2.34+** installed locally (`git --version` to check — earlier versions don't support SSH signing)
- **SSH key** for GitHub authentication (the same key you use for `git push` will be reused for signing)
- **macOS, Linux, or WSL**: any POSIX shell. All command examples assume `bash`/`zsh`.

If you need to generate a new SSH key, follow [GitHub's official guide](https://docs.github.com/en/authentication/connecting-to-github-with-ssh/generating-a-new-ssh-key-and-adding-it-to-the-ssh-agent) — prefer `ed25519` (`ssh-keygen -t ed25519 -C "your-email@weown.email"`).

---

## 2. First-Time Developer Setup

### 2.1 Clone the repository

```bash
git clone git@github.com:WeOwnNetwork/ai.git
cd ai
```

### 2.2 Configure your Git identity

Your `user.name` and `user.email` are recorded in every commit. Use your real name and your WeOwn email:

```bash
git config user.name "Your Full Name"
git config user.email "your-email@weown.email"
```

(Omit `--global` if you use different identities for personal vs. work repos; otherwise `--global` is fine.)

### 2.3 Enable commit signing — see §3 below. This is not optional

### 2.4 Verify you can push

Make a throwaway branch and push an empty commit to confirm auth + signing work end-to-end:

```bash
git checkout -b feature/<yourname>-test-signing
git commit --allow-empty -m "test: verify commit signing works"
git push origin feature/<yourname>-test-signing

# Verify the commit is signed:
git log -1 --pretty='format:%h %G? %GS %s'
# Expected output: a 7-char hash, then 'G', then your name, then 'test: verify...'
# If %G? shows 'N' (unsigned), see §8 Troubleshooting.

# Then clean up:
git checkout main
git push origin --delete feature/<yourname>-test-signing
git branch -D feature/<yourname>-test-signing
```

The `auto-pr-to-main.yml` workflow will open a test PR when you push — just close it without merging.

---

## 3. Commit Signing (REQUIRED)

**Every commit merged to `main` must be cryptographically signed.** This is enforced by a GitHub branch protection rule — unsigned commits will be rejected at merge time.

### Why we require signed commits

- **Authenticity**: Proves that the person with the private key actually authored the commit. Without signing, `user.name` and `user.email` are unverified metadata — anyone can spoof them.
- **Integrity**: Detects tampering — if any byte of the commit is modified after signing, the signature fails.
- **Compliance**: Satisfies **SOC 2 CC7.1** (system integrity), **ISO/IEC 27001 A.8.28** (secure coding), **NIST CSF PR.DS-6** (integrity checking), **CIS Controls v8 16.12** (code integrity).
- **Audit trail**: GitHub displays a green "Verified" badge on every signed commit, providing evidence for security audits.

### 3.1 One-time setup (takes ~5 minutes)

We use **SSH-based signing** — no GPG required. Your existing SSH key (the one you use for `git push`) is reused for signing. Run these seven steps once per machine:

```bash
# 1. Tell Git to sign with SSH keys (not GPG)
git config --global gpg.format ssh

# 2. Point at your SSH public key (adjust filename if yours differs)
#    Run `ls ~/.ssh/*.pub` first to see your available keys.
git config --global user.signingkey ~/.ssh/id_ed25519.pub

# 3. Sign every commit automatically
git config --global commit.gpgsign true

# 4. Sign every tag automatically
git config --global tag.gpgsign true

# 5. Verify your Git identity uses an email that is VERIFIED on your
#    GitHub account. Check at https://github.com/settings/emails.
#    GitHub matches the commit's committer email to a GitHub account
#    via the verified-emails list; a mismatch causes "Unverified" on
#    the commit page even when the signature is cryptographically valid.
git config --global user.email "your-github-verified-email@example.com"
git config --global user.name  "Your Full Name"

# 6. Create an allowed-signers file so Git can verify SSH signatures
#    LOCALLY (e.g., via `git log --show-signature` or `%G?`).
#    This is a purely-local verification aid; GitHub verifies signatures
#    server-side and does not need this file. Without it, locally-run
#    `git log -1 --pretty=%G?` returns 'N' and emits the error:
#      "gpg.ssh.allowedSignersFile needs to be configured and exist
#       for ssh signature verification"
#    even when the commit IS properly signed.
mkdir -p ~/.config/git
# Write one line: <email> <ssh-public-key-contents>
echo "$(git config --global --get user.email) $(cat ~/.ssh/id_ed25519.pub)" \
  > ~/.config/git/allowed_signers
git config --global gpg.ssh.allowedSignersFile ~/.config/git/allowed_signers

# 7. Verify your full config
git config --global --list | grep -E 'gpg|sign|^user\.'
# Expected (order may vary):
#   user.name=Your Full Name
#   user.email=your-github-verified-email@example.com
#   user.signingkey=/Users/you/.ssh/id_ed25519.pub
#   gpg.format=ssh
#   gpg.ssh.allowedsignersfile=/Users/you/.config/git/allowed_signers
#   commit.gpgsign=true
#   tag.gpgsign=true
```

> **Why `allowed_signers`?** SSH signatures are a newer Git feature than GPG signatures. Unlike GPG (which has a global public-key chain Git can look up), SSH signing requires a local file mapping trusted emails → public keys. Without this file, Git cannot verify SSH signatures locally and reports `N` (no signature / unverifiable) in `%G?` output — a common first-run gotcha that makes you think signing failed when it actually succeeded.

### 3.2 Register your public key on GitHub as a *Signing Key*

Your SSH key must be listed on GitHub **twice** — once as an Authentication Key (for `git push`), once as a **Signing Key** (for verifying signatures). They're separate entries even when the key material is identical.

1. Copy your public key to clipboard:

   ```bash
   # macOS:
   cat ~/.ssh/id_ed25519.pub | pbcopy
   # Linux:
   cat ~/.ssh/id_ed25519.pub | xclip -selection clipboard
   ```

2. Go to [GitHub → Settings → SSH and GPG keys](https://github.com/settings/keys) → **New SSH key**.
3. Fill in:
   - **Title**: `SSH signing key — <machine name>` (e.g., `SSH signing key — laptop`)
   - **Key type**: **`Signing Key`** ← ⚠️ This is a dropdown! The default is Authentication. You must change it.
   - **Key**: paste the contents of your `.pub` file
4. Click **Add SSH key**. GitHub may ask for your password / 2FA.

After this, you'll see your key listed under **both** "Authentication keys" and "Signing keys" sections. That's correct.

### 3.3 Verify signing works

Make an empty commit and inspect it:

```bash
git commit --allow-empty -m "test: verify signing"
git log -1 --show-signature
# Look for: "Good \"git\" signature for your-email@weown.email with ED25519 key SHA256:..."

git log -1 --pretty='format:%h %G? %GS %s'
# %G? meanings:
#   G = Good signature (local verification passed — §3.1 step 6 is wired up)
#   U = Good but untrusted (signed correctly, but signer not in allowed_signers)
#   N = Cannot verify locally (usually: allowed_signers file missing — §3.1 step 6)
#   B = Bad signature (signature present but invalid — something's corrupted)
#   X = Good but expired

# If you're unsure whether the commit has a signature at all, inspect the raw object:
git cat-file -p HEAD | head -20
# A signed commit shows a `gpgsig -----BEGIN SSH SIGNATURE-----` block.
```

If `%G? = N` but `git cat-file -p HEAD` shows a `gpgsig` block → the signature is present; local verification is broken. Re-run §3.1 step 6. See [§8 Troubleshooting](#8-troubleshooting-signed-commits).

If `%G? = N` AND `git cat-file` shows NO `gpgsig` block → the commit genuinely wasn't signed. See [§8 Troubleshooting](#8-troubleshooting-signed-commits).

Once you see `G`, you're done. **All future commits sign automatically** — you never think about it again.

### 3.4 What signing does NOT do

- **Does not encrypt anything** — commit contents are still plaintext in the repo. Signing is about *authentication*, not *confidentiality*.
- **Does not prevent identity changes** — you can still change `user.name`/`user.email` freely. Signing just binds the name to a key that only you hold.
- **Does not cover your SSH private key loss** — if your laptop is stolen, rotate the key (see §3.5).

### 3.5 Rotating your signing key

If your laptop is lost/stolen or you suspect key compromise:

1. Immediately: GitHub → Settings → SSH and GPG keys → **Delete** the compromised key (both Authentication and Signing entries for that key).
2. Generate a new SSH key on a trusted device: `ssh-keygen -t ed25519 -C "your-email@weown.email"`.
3. Repeat §3.1 and §3.2 with the new key.
4. All **past** commits signed with the old key will show as "Unverified" on GitHub after deletion, but their git-native signatures remain in history. Author attribution (name/email) is unaffected.

---

## 4. Branching Model (GitHub Flow) & Naming Convention

### 4.1 The Model — GitHub Flow

This repo uses **[GitHub Flow](https://docs.github.com/en/get-started/using-github/github-flow)** — the simplest trunk-based branching model, designed for continuous-delivery teams.

**In one sentence**: `main` is always shippable; every change lives on a short-lived branch; every branch is merged back to `main` via a reviewed PR; the branch is deleted after merge.

**Lifecycle (per change)**:

```
       (branch off main)         (push)          (review)         (merge)        (delete)
  main ────────┬──────────────────────────────────────────────────┬──────────────────►
               │                                                   │
               └──► feature/roman-add-foo ─(commits)─► PR #N ─(approve)─┘
                    (short-lived; typically hours to days)
```

1. **Branch off `main`** with a conforming name (see §4.4)
2. **Commit** your work (signed — see §3). Push frequently.
3. **PR opens automatically** when you push — the `auto-pr-to-main.yml` workflow (see §6) creates it from `weown-bot` to trigger Copilot auto-review
4. **Iterate** based on Copilot + human review; resolve threads as you address them
5. **Squash-merge via GitHub UI** once §6.4 requirements are met — then **delete the branch** (GitHub UI offers a "Delete branch" button on merged PRs; always click it)

### 4.2 What GitHub Flow is NOT

We explicitly do **not** use:

- **Git Flow** (long-lived `develop`, `release/*`, recurring `hotfix/*` branches off `develop`) — too heavyweight for a small, CD-oriented team; adds merge-conflict surface area
- **Direct commits to `main`** — blocked by branch protection; would bypass Copilot review, 2-approval rule, signed-commit rule, and CODEOWNERS
- **Fork-based contribution** — this is a trusted internal repo; collaborators push directly to branches within the org

### 4.3 Why GitHub Flow fits WeOwn

| Rationale | How GitHub Flow delivers |
|---|---|
| **Simplicity** | One long-lived branch (`main`); everything else is ephemeral |
| **Continuous delivery** | `main` is always deployable — any commit on `main` can be shipped |
| **SOC 2 CC8.1** (change management) | Every change reaches `main` via a reviewed, logged, approved PR — no backchannels |
| **Small-team fit** | No release-branch reconciliation overhead; review happens once per change |
| **Audit posture** | Branch protection only needs to guard one branch; all history on `main` is reviewed + signed |
| **Future-proof** | Release tagging, Helm OCI publishing, or feature flags layer cleanly on top without restructuring |

### 4.4 Branch Naming Convention

All branches pushed to this repo must match this pattern (enforced by [`.github/workflows/branch-name-check.yml`](.github/workflows/branch-name-check.yml)):

```
<type>/<dev>-<short-description>
```

#### Reserved types

| Type | Use for |
|---|---|
| `feature/` | New functionality, enhancements |
| `fix/` | Bug fixes |
| `docs/` | Documentation-only changes |
| `hotfix/` | Urgent production fixes — may skip full review process per [`.github/INCIDENT_RESPONSE.md`](.github/INCIDENT_RESPONSE.md) |

> **Note on `hotfix/`**: in GitHub Flow `hotfix/` is **just a naming prefix to signal urgency** — it still follows the same branch-from-`main` → PR → merge cycle. It is **not** a Git-Flow-style long-lived hotfix branch off a release tag.

#### `<dev>`

Your short handle (lowercase, no spaces) — typically your first name. Examples: `roman`, `nik`, `mohammed`, `shahid`, `dhruv`. This is for **human-readable branch naming only** — the auto-PR workflow attributes the PR via GitHub's commits API and event context, **not** branch-name parsing. So `<dev>` does not need to match your GitHub handle. See the Known contributor handles table below for current contributors.

> **Branch name vs. PR body — different identifiers, different jobs (by design).**
>
> | Where it appears | Value | Example |
> |---|---|---|
> | Branch name `<dev>` segment | Short handle / first name / alias | `roman`, `nik`, `mohammed` |
> | PR body `Opened by:` line | GitHub @handle of the FIRST commit's author (idempotent across pushes) | `@romandidomizio` |
> | PR body `Last pushed by:` line | GitHub @handle of whoever pushed THIS run | `@ncimino` |
> | PR body `Contributors on this branch:` list | All GitHub @handles + commit counts | `- @romandidomizio (4 commits)` |
>
> The PR body shows a three-tier attribution model:
>
> - **`Opened by:`** is resolved from `git rev-list --reverse` → `gh api /repos/.../commits/{first-sha}`. Stable across pushes because the **"Copilot auto-review" ruleset** (id 12131972, see [ADR-004](.github/ADR-004-copilot-auto-review-ruleset.md)) enforces `non_fast_forward` on `~ALL` branches in this repo, blocking the rebase / force-push that would change first-commit identity.
> - **`Last pushed by:`** uses `${{ github.triggering_actor || github.actor }}` — `triggering_actor` for `workflow_dispatch` / re-runs, `github.actor` as fallback for plain pushes.
> - **`Contributors on this branch:`** aggregates per-commit GitHub logins on the branch range with commit counts. Falls back to commit author **name only** (no email — emails are PII and intentionally not surfaced in the public PR body) for unlinked external contributors.
>
> You don't need to keep `<dev>` in sync with your GitHub handle; the platform knows who authored each commit and who pushed each run, and the workflow reports all three views directly. See `.github/workflows/auto-pr-to-main.yml` steps 6 + 7.

#### `<short-description>`

3–6 words describing the change, lowercase, hyphen-separated, no underscores. Keep it under ~40 chars total branch name.

#### Examples

```
✅ feature/roman-add-pat-health-check
✅ fix/nik-resolve-tls-warning
✅ docs/mohammed-update-compliance-roadmap
✅ hotfix/shahid-patch-auth-bypass
✅ feature/dhruv-k8s-argo-migration

❌ my-branch                         (missing type/)
❌ feature/Roman-Add-Thing           (uppercase)
❌ feature/roman_add_thing           (underscores, not hyphens)
❌ feature/ab-a                      (first description segment <3 chars)
❌ feature/roman--double-hyphen      (double hyphens)
❌ feature/roman-add-thing-that-is-very-long-and-hard-to-read  (too long)
❌ random/roman-test                 (wrong type prefix)
```

Regex: `^(feature|fix|docs|hotfix)/[a-z0-9]{2,}-[a-z0-9]{3,}(-[a-z0-9]+)*$`

- `<dev>` = 2+ alphanumeric chars
- First `<description>` segment = 3+ alphanumeric chars (so `feature/ab-a` is rejected)
- Additional `-word` segments = 1+ alphanumeric chars each

**Convention beyond the regex**: the `<dev>` segment should be a recognizable short handle — typically your first name or alias (examples: `roman`, `nik`, `mohammed`, `shahid`, `dhruv`). This is for human-readable branch naming and audit trails; it is **not** used for PR attribution. Reviewers verify the `<dev>` segment is recognizable during PR review.

**Example of regex-valid but convention-violating**: `feature/add-thing` technically passes the regex (`add` satisfies the 2+ char `<dev>` slot, `thing` satisfies the 3+ char description slot), but `add` is not a meaningful contributor handle and the branch name is not human-readable. A reviewer should ask the author to rename to e.g. `feature/roman-add-thing` before merge. (The PR body's `Opened by:`, `Last pushed by:`, and `Contributors on this branch:` fields will still attribute correctly regardless — see next paragraph.)

The `auto-pr-to-main.yml` workflow attributes the PR via three independent GitHub-context sources:

- **`Opened by:`** — the GitHub @handle of the FIRST commit's author on the branch, resolved via `gh api /repos/.../commits/{first-sha}`. Stable across pushes because the first commit is immutable under the `non_fast_forward` ruleset.
- **`Last pushed by:`** — `${{ github.triggering_actor || github.actor }}`. The workflow currently runs on `push` (resolves to the pusher) and `workflow_dispatch` (resolves to whoever clicked Run); `triggering_actor` is preferred because it remains accurate on re-runs, with `github.actor` as the fallback.
- **`Contributors on this branch:`** — per-commit GitHub @handles with commit counts, aggregated across the branch range.

No branch-name parsing, no maintenance-prone handle mapping. See `.github/workflows/auto-pr-to-main.yml` steps 6 + 7. The PR body shows real GitHub usernames (`@ncimino`, `@romandidomizio`, etc.) when available and otherwise falls back to commit-author names (for commits where the commits API doesn't return a linked GitHub login — e.g., unlinked email addresses), regardless of what `<dev>` segment was chosen for the branch name.

#### Known contributor handles

For internal contributors, use your `<dev>` segment from the table below. External or first-time contributors may use any descriptive short handle — PR attribution will still be accurate via `${{ github.triggering_actor || github.actor }}` regardless of what appears in the branch name. To formally register as a recurring contributor, open a `docs/<your-handle>-add-to-contributors` PR adding your row to this table (exercises the branch-naming workflow + ruleset end-to-end).

| GitHub handle | Branch `<dev>` segment |
|---|---|
| `@romandidomizio` | `roman` |
| `@ncimino` | `nik` |
| `@YonksTEAM` | `yonks` |
| `@iamwaseem18` | `mohammed` |
| `@mshahid538` | `shahid` |
| `@dhruvmalik007` | `dhruv` |

When a contributor leaves, remove the row from this public table and update `.github/CODEOWNERS` to remove their active rule participation. (Extended context — legal names, roles, tenure — lives in internal onboarding docs, not in this public repo.)

#### Enforcement posture (current: reviewer-enforced convention)

This repo currently uses **reviewer-enforced convention** for `<dev>` identity (the regex enforces format only). Two stricter options are available if team growth or compliance findings warrant — see `.github/ADR-003-main-branch-ruleset.md` for decision record + upgrade criteria. Summary:

| Posture | Mechanism | When to use |
|---|---|---|
| **Current — reviewer-enforced** | Regex enforces format only; reviewer verifies `<dev>` against the table above | Team ≤ ~15 contributors with external contributions expected |
| **Warning layer (Option C)** | Regex + a workflow step emits `::warning::` if `<dev>` is not in a YAML allowlist | Team grows past ~15, or audit finding about attribution inconsistency, or repeated misuse observed. Non-blocking — reviewer can still approve external contributions. |
| **Strict allowlist (Option A)** | Regex itself includes an alternation of known handles (`(roman\|nik\|mohammed\|…)`) | Stable internal-only team ≥ 15, external contributions are rare/gated separately, and compliance mandates mechanical enforcement of attribution. High maintenance: regex must be updated for every onboarding/offboarding. |

Trigger to revisit: quarterly ruleset review (see `.github/ADR-003` §Review Cadence) or sooner if any of the upgrade criteria materialize.

### 4.5 Branch lifetime expectations

| Phase | Expected duration |
|---|---|
| Branch opened → first push | Minutes |
| First push → PR reviewed | 1–2 business days |
| PR reviewed → merged | Same day as final approval |
| Merged → branch deleted | **Immediately after merge** (use the GitHub UI's "Delete branch" button) |

Long-lived feature branches (>1 week) increase merge conflict risk and stale-review risk. If a change is too big for GitHub Flow, split it into smaller PRs or use a feature flag.

---

## 5. Commit Message Conventions

### Summary line (first line)

- **≤72 characters**
- Format: `<type>(<scope>): <imperative subject>`
- Example: `feat(pr7): add PAT health check workflow`

Common `<type>` values (inspired by Conventional Commits, not strictly enforced):

| Type | Use |
|---|---|
| `feat` | New feature |
| `fix` | Bug fix |
| `docs` | Documentation-only change |
| `refactor` | Code change that neither fixes a bug nor adds a feature |
| `test` | Adding or correcting tests |
| `chore` | Tooling, CI, dependencies |
| `security` | Security-related fix (may include CVE reference) |

### Body (optional but encouraged)

- Separate from summary with a blank line
- Explain **why**, not what (the diff shows what)
- Wrap at ~72 chars for readability in terminals
- Reference PR, issue, ADR, or CVE numbers when relevant

### Example

```
feat(pr7): add PAT health check workflow (v3.3.4.1)

Adds a scheduled GitHub Actions workflow that verifies the
weown-bot PAT validity weekly and opens a rotation reminder
issue when expiration is within 14 days (hard-fails at 3 days).

Refs: ADR-001, .github/workflows/README.md §7
Compliance: SOC 2 CC7.2, NIST DE.CM-7
```

---

## 6. Pull Request Workflow

### 6.1 Create a branch and push

```bash
git checkout main
git pull origin main
git checkout -b feature/<yourname>-<description>
# ... make changes ...
git add -A
git commit                   # opens editor — use conventional format above
# (Commit is signed automatically thanks to your §3 setup)
git push origin feature/<yourname>-<description>
```

### 6.2 Automatic PR creation

Pushing a branch that matches the naming pattern triggers [`auto-pr-to-main.yml`](.github/workflows/auto-pr-to-main.yml), which:

1. Opens a PR from your branch to `main` **authored by `weown-bot`** (this is what triggers GitHub Copilot's auto-review)
2. Populates the PR body with a phase-aware compliance checklist + full commit log
3. Assigns reviewers per [`.github/CODEOWNERS`](.github/CODEOWNERS)
4. **If a PR already exists for your branch**, the workflow updates the body + reviewers instead of creating a duplicate — so every push keeps the checklist current

### 6.3 Iterate

- Push additional commits as you respond to review
- Each push re-runs the workflow, keeping the PR up to date
- Resolve each Copilot/human conversation thread as you address it (use "Resolve conversation" button)

### 6.4 Merge requirements

Before merging to `main`, your PR must satisfy **all** of:

- ✅ All commits signed (green "Verified" badge on every commit) — [§3](#3-commit-signing-required)
- ✅ `branch-name-check.yml` status check passing
- ✅ Copilot AI review completed
- ✅ 1 human approval (enforced by branch protection + CODEOWNERS)
- ✅ All conversation threads resolved
- ✅ Up-to-date with `main` (rebase if needed)

Preferred merge strategy: **Squash merge via GitHub UI** — creates a single clean commit on `main` signed by GitHub's internal key.

### 6.5 After merge — close the GitHub Flow loop

**Delete your branch immediately after the PR is merged.** GitHub offers a one-click "Delete branch" button on merged PRs — use it. Leaving merged branches around accumulates clutter, confuses future contributors, and has no upside (git history is preserved on `main` regardless).

If you forget, clean up later:

```bash
# Delete local tracking branches for branches already merged & deleted on GitHub
git fetch --prune

# Delete a specific local branch
git branch -D feature/<yourname>-<description>
```

See §4.5 for expected branch lifetimes.

---

## 7. Code Review Expectations

- **Respond within 2 business days** of a review request
- **Resolve threads you addressed** (don't leave them open)
- **Ask before force-pushing** if reviews are in flight (force-push invalidates review state for amended commits)
- **Be explicit about known limitations** — reviewers aren't mind-readers
- **When Copilot and a human conflict** — the human is authoritative; document the rationale in the thread

See [`.github/copilot-instructions.md`](.github/copilot-instructions.md) for Copilot's specific review directives and the framework checklist it applies.

---

## 8. Troubleshooting Signed Commits

### "`%G?` shows `N` (cannot verify), but I think signing is set up"

**First, check whether the signature is actually present in the commit:**

```bash
git cat-file -p HEAD | head -20
```

If you see a `gpgsig -----BEGIN SSH SIGNATURE-----` block → **the commit IS signed**, local verification just can't run. Proceed to cause 1 below.

If you see NO `gpgsig` block → the commit is genuinely unsigned. Skip to causes 2–5.

---

**Cause 1 (most common on fresh setups): `allowed_signers` file missing or not configured.**

Symptom: running `git log --show-signature` prints:

```
error: gpg.ssh.allowedSignersFile needs to be configured and exist for ssh signature verification
```

Fix:

```bash
mkdir -p ~/.config/git
echo "$(git config --global --get user.email) $(cat ~/.ssh/id_ed25519.pub)" \
  > ~/.config/git/allowed_signers
git config --global gpg.ssh.allowedSignersFile ~/.config/git/allowed_signers

# Re-verify
git log -1 --pretty='format:%h %G? %GS %s'
# Should now print 'G' instead of 'N'
```

This is a pure LOCAL verification fix. GitHub verifies signatures server-side and never uses this file. See [§3.1 step 6](#31-one-time-setup-takes-5-minutes) for the full setup flow.

---

**Cause 2: `commit.gpgsign` not set to `true`**:

```bash
git config --global --get commit.gpgsign
# Should print: true
git config --global commit.gpgsign true  # fix
```

**Cause 3: `gpg.format` not `ssh`**:

```bash
git config --global --get gpg.format
# Should print: ssh
git config --global gpg.format ssh  # fix
```

**Cause 4: `user.signingkey` path wrong or missing**:

```bash
git config --global --get user.signingkey
# Should print: /Users/you/.ssh/id_ed25519.pub (absolute path)
ls -la $(git config --global --get user.signingkey)  # verify the file exists
```

**Cause 5: Git version too old** (< 2.34 doesn't support SSH signing):

```bash
git --version
# If < 2.34.0, upgrade. On macOS: `brew upgrade git`. On Linux: your package manager.
```

**Cause 6: Repo-local override of `commit.gpgsign`**:

```bash
git config --get commit.gpgsign  # effective value for THIS repo (local > global)
git config --local --get commit.gpgsign  # explicit local override (if any)
# If the local value is 'false', remove the override:
git config --local --unset commit.gpgsign
```

---

### "Commit signs locally (`%G? = G`) but GitHub shows `Unverified`"

Two possible causes. Click the "Unverified" label on the commit page — GitHub tells you which:

**Cause A: Your signing key isn't registered on GitHub as a Signing Key**

It might only be listed as an Authentication Key. GitHub treats the two entries separately — even with the same key material, you need a distinct "Signing Key" entry.

Fix: [GitHub → Settings → SSH and GPG keys](https://github.com/settings/keys) → **New SSH key** → **Key type: Signing Key** → paste the same `id_ed25519.pub` content.

Past commits need no re-signing — GitHub re-verifies when it next renders the page.

**Cause B: Your committer email isn't verified on your GitHub account**

GitHub uses the commit's committer email to look up which GitHub account owns the signature. If the email isn't in your [verified emails list](https://github.com/settings/emails), GitHub can't tie the signature to your account, even when the cryptography is perfect.

Fix (pick one):

- **Add the email to GitHub** — [Settings → Emails → Add email](https://github.com/settings/emails) → click the verification link in the confirmation email. Done.
- **Change `user.email` to one that IS verified** — then amend the commit:

  ```bash
  # Use whichever email IS on https://github.com/settings/emails
  git config --global user.email "your-github-verified-email@example.com"

  # Update allowed_signers to match so local verification still works
  echo "$(git config --global --get user.email) $(cat ~/.ssh/id_ed25519.pub)" \
    > ~/.config/git/allowed_signers

  # Amend the last commit to pick up the new committer email + re-sign
  git commit --amend --no-edit --reset-author

  # If you have NOT pushed yet, you're done — push normally.
  # If you already pushed, force-push is BLOCKED by the non_fast_forward ruleset.
  # Use the close+recreate path in "My PR is blocked — commits are unsigned" below.
  ```

### "My PR is blocked — commits are unsigned"

If your PR shows "Merge blocked — requires signed commits", the only viable path is to **close the PR and recreate it with signed commits**. The `non_fast_forward` ruleset on `~ALL` branches (see [ADR-004](.github/ADR-004-copilot-auto-review-ruleset.md)) blocks force-push, so rebase + force-push is not possible.

```bash
# Step 1: Close the blocked PR in GitHub UI (just click Close)

# Step 2: Complete §3.1 signing setup first if you haven't already
git config --global commit.gpgsign true
git config --global gpg.format ssh
git config --global user.signingkey ~/.ssh/id_ed25519.pub

# Step 3: Create a fresh branch from main
git fetch origin main
git checkout -b feature/<yourname>-<new-description> origin/main

# Step 4: Cherry-pick your changes with explicit signing
git cherry-pick -S <commit-sha-from-old-branch>
# Repeat for each commit you want to keep

# Step 5: Push and let auto-PR create a new one
git push origin feature/<yourname>-<new-description>
```

This creates a new PR with 100% signed commits from the start. Link to the old closed PR in the body for context.

### "Copilot review didn't start on my auto-created PR"

**Normal for the first commit on a new branch.** Copilot evaluates auto-review eligibility at **PR-creation time**, not push time. When `auto-pr-to-main.yml` creates the PR via `gh pr create`, the commits already exist on the branch — there is no "new push to an existing PR" event for Copilot to hook.

**What to do**: Make any follow-up push to the same branch (even a trivial whitespace fix or comment addition). Copilot will review the new push. All subsequent pushes on the same open PR are reviewed automatically.

**Verification**: Check the PR timeline for `Copilot AI review requested due to automatic review settings`. If you see this entry, the ruleset fired correctly — Copilot just needs a "new push" event to analyze. If the entry is missing entirely, check ADR-004 § Empirical Validation Results.

---

### "I'm getting `error: gpg failed to sign the data`"

Typically means SSH agent isn't running or your key has a passphrase. Solutions:

```bash
# Start the ssh-agent and add your key
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519
# macOS: persist agent via keychain
ssh-add --apple-use-keychain ~/.ssh/id_ed25519
```

If your key is passphrase-protected and you're on macOS, add to `~/.ssh/config`:

```
Host *
  UseKeychain yes
  AddKeysToAgent yes
  IdentityFile ~/.ssh/id_ed25519
```

---

## 9. Compliance & Governance References

- **Code review directives**: [`.github/copilot-instructions.md`](.github/copilot-instructions.md)
- **Workflows operational reference**: [`.github/workflows/README.md`](.github/workflows/README.md)
- **Service account rationale**: [`.github/ADR-001-service-account-pat.md`](.github/ADR-001-service-account-pat.md)
- **Secret management**: [`.github/ADR-002-infisical-github-sync.md`](.github/ADR-002-infisical-github-sync.md)
- **Security assessment**: [`.github/SECURITY_ASSESSMENT.md`](.github/SECURITY_ASSESSMENT.md)
- **Incident response**: [`.github/INCIDENT_RESPONSE.md`](.github/INCIDENT_RESPONSE.md)
- **Compliance roadmap**: [`docs/COMPLIANCE_ROADMAP.md`](docs/COMPLIANCE_ROADMAP.md)
- **Versioning methodology**: [`docs/VERSIONING_WEOWNVER.md`](docs/VERSIONING_WEOWNVER.md)
- **Code ownership**: [`.github/CODEOWNERS`](.github/CODEOWNERS)

---

## Questions?

- **Technical questions about the repo**: open an issue with label `question`
- **Security concerns**: see [`.github/SECURITY_ASSESSMENT.md` §Incident Response](.github/SECURITY_ASSESSMENT.md) — do NOT open a public issue for security vulnerabilities
- **Process / governance**: contact `@ncimino` (Nik) or reach out via [`.github/CODEOWNERS`](.github/CODEOWNERS)

Thanks for contributing. 🚀
