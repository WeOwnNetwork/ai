# WeOwn Dev Onboarding — Zed + Governance Setup

| Field | Value |
|---|---|
| **Document** | `docs/onboarding/ZED_DEV_SETUP.md` |
| **Version** | `v4.1.1.1` (#WeOwnVer — confirm WEEK/ITERATION offset vs `docs/VERSIONING_WEOWNVER.md` at merge) |
| **Date** | 2026-06-03 (W23) · #WeOwnSeason004 🚀 |
| **Status** | 📝 DRAFT — pending @CTO review |
| **Maintained by** | @CTO (Nik) |
| **Audience** | Every WeOwn developer working in **Zed** against `WeOwnNetwork/ai` |
| **Why** | Stop the recurring mistakes (public-repo leaks, branch naming, missing PR hygiene) by loading our governance into your editor *before* you write code. Mantra L-420: **DOCUMENT → ITERATE → AUTOMATE.** |

> **Read this once, top to bottom, on day 1. It takes ~30–45 min. When you finish, your Zed agent
> enforces our rules automatically, your WeOwnLLM agent knows our governance, and your first PR passes CI.**

---

## The three layers you're setting up

| Layer | What it is | How you "get" it | Where it lives |
|---|---|---|---|
| 1. **Business governance** (#FedArch) | How WeOwn operates: CCC-IDs, protocols, learnings, rules | Clone `CCCbotNet/fedarch` + RAG-sync it into your WeOwnLLM workspace | `fedarch` repo + your AnythingLLM RAG |
| 2. **The codebase** | The infra/app monorepo you build in | Clone `WeOwnNetwork/ai` | `ai` repo |
| 3. **Dev governance** (AI guidance) | The rules your AI agent obeys while coding | Global Zed `AGENTS.md` + the repo's `.rules` (auto-loaded) | `~/.config/zed/AGENTS.md` + `ai/.rules` |

You need all three. Layer 3 is the one most people skip — and it's why the mistakes happen.

---

## Prerequisites (get these from @CTO / @GTM first)

- [ ] A `@weown.net` email + 2FA
- [ ] Membership in the **`WeOwnNetwork`** GitHub org (accept the invite) — and view access to **`CCCbotNet/fedarch`** (public)
- [ ] An **Infisical** login + access to the project(s) for your work
- [ ] A **WeOwnLLM** (AnythingLLM) account on your assigned instance, with **ADMIN** role on your own workspace (needed to add the RAG connector)
- [ ] (If you do infra) **DigitalOcean** team access + kubeconfig, and `doctl`
- [ ] Tools installed: `git`, [`gh`](https://cli.github.com/), [Zed](https://zed.dev), `infisical`, `tofu` (OpenTofu), `pre-commit`, `doctl` (infra only)

---

## Step 1 — Clone both repos

```bash
mkdir -p ~/projects && cd ~/projects
gh repo clone WeOwnNetwork/ai        # or: git clone https://github.com/WeOwnNetwork/ai.git
gh repo clone CCCbotNet/fedarch      # or: git clone https://github.com/CCCbotNet/fedarch.git
```

You now have the codebase (`ai`) and the business governance (`fedarch`) locally.

---

## Step 2 — Install the GLOBAL dev-governance rules into Zed

These apply in **every** repo you open in Zed (the cross-repo "senior engineer" baseline).

```bash
# macOS / Linux:
mkdir -p ~/.config/zed
cp ~/projects/ai/docs/onboarding/zed-global-AGENTS.md ~/.config/zed/AGENTS.md
# Windows (PowerShell):
#   Copy-Item "$HOME\projects\ai\docs\onboarding\zed-global-AGENTS.md" "$env:APPDATA\Zed\AGENTS.md"
```

Zed feeds `~/.config/zed/AGENTS.md` into every Agent Panel conversation automatically. Open it and read it — it's short.

> ⚠️ If you ever paste a "default rule" in Zed's Rules Library, Zed *appends* it to this same global `AGENTS.md`. Keep this file as the source of truth and re-copy it from the repo when it's updated.

---

## Step 3 — Confirm the PROJECT rules auto-load

The `ai` repo ships a root **`.rules`** file. Zed auto-loads the **first** rules file it finds at a repo
root, in this order:

```
.rules → .cursorrules → .windsurfrules → .clinerules → .github/copilot-instructions.md
       → AGENT.md → AGENTS.md → CLAUDE.md → GEMINI.md
```

So in `ai`, Zed loads **`.rules`** (which is why it exists — it's concise and points to the deeper docs).
Verify:

```bash
cd ~/projects/ai
sed -n '1,20p' .rules        # the WeOwn non-negotiables header
```

Open the repo in Zed → open the **Agent Panel** → it should show the project rules file is active. Read
`.rules` in full (2 min). It is the single most important file for not making the mistakes below.

> Note: because Zed stops at the first match, it does **not** separately load `.github/copilot-instructions.md`
> or `CLAUDE.md`. `.rules` references them; read those two as well (Step 6) — they hold the full detail.

---

## Step 4 — RAG-sync #FedArch into your WeOwnLLM workspace

This gives your **WeOwnLLM (AnythingLLM) agent** the business governance, so it answers in-context
(CCC-IDs, protocols, learnings). Full guide: **`fedarch/_GUIDES_/GUIDE-006`**.

1. Create a **fine-grained, read-only** GitHub PAT scoped to `CCCbotNet/fedarch` only
   (GitHub → Settings → Developer settings → Fine-grained tokens). 90-day expiry. **Contents: Read-only.**
2. In your AnythingLLM workspace (ADMIN) → **Data Connectors → GitHub Repo** → repo
   `https://github.com/CCCbotNet/fedarch`, branch `main`, paste the PAT → **Collect & Embed**.
3. Pin the core docs in your workspace context: **SharedKernel.md · CCC.md · PROTOCOLS.md · BEST-PRACTICES.md**.

> 🔒 The PAT is a secret — it lives in AnythingLLM only. Never paste it into a repo file, a commit, or chat.

---

## Step 5 — Wire Infisical (secrets) for local work

```bash
infisical login                       # your own login = auditable, revocable
infisical run -- <your command>       # injects secrets at runtime; nothing lands on disk
```

Never create a `.env` with real values. Commit `.env.example` with placeholders only. (Details: the
repo's `CLAUDE.md` "Secret Management" + `.github/copilot-instructions.md` §3.10.)

---

## Step 6 — Read the must-reads (don't skip — this is the "why")

**Dev governance (in `ai`):**

- [ ] `.rules` — the non-negotiables (you read this in Step 3)
- [ ] `.github/copilot-instructions.md` — **§3.0 public-repo redaction** + **§3.10 secrets** especially
- [ ] `CLAUDE.md` — branch naming, copier `*-docker/` pattern, hardening checklist
- [ ] `docs/VERSIONING_WEOWNVER.md` — the `#WeOwnVer` stamp every doc/PR carries
- [ ] Reference deployment: `anythingllm-docker/DEPLOYMENT_GUIDE.md` + `…/sites/s004.ccc.bot/MIGRATION_RUNBOOK.md`

**Business governance (in `fedarch`):**

- [ ] `_SYS_/SharedKernel.md`, `_SYS_/CCC.md`, `_SYS_/PROTOCOLS.md`, `_SYS_/BEST-PRACTICES.md` (the PinnedDocs)
- [ ] `_GUIDES_/GUIDE-012` — #ResponsibleAgenticAI (the 12 principles; #1 is #OnlyHumanApproves)
- [ ] `_GUIDES_/GUIDE-015` — Agent Initiation ("Search before declaring, prove before verifying")

---

## Step 7 — Verify your setup (prove it works)

1. **Agent knows the rules:** in Zed's Agent Panel, ask *"What are the public-repo redaction rules for this
   repo and what's our branch-naming pattern?"* — it should answer from `.rules` (placeholders, RFC 5737, the
   regex). If it doesn't, your rules file isn't loading — recheck Steps 2–3.
2. **Pre-commit is on:** `cd ~/projects/ai && pre-commit install` (setup: `docs/PRECOMMIT.md`). It runs
   gitleaks + yamllint + shellcheck before each commit.
3. **Do a trivial PR end-to-end** to exercise the gates:

   ```bash
   git checkout -b docs/<yourhandle>-onboarding-smoke-test
   # make a 1-line doc edit, commit, push
   gh pr create --fill
   ```

   Confirm all CI checks go green (Branch Name, Lint, Security, Documentation, Compliance, WeOwnVer).
   Then close it. You've now seen every gate your real PRs must pass.

---

## 🚨 The non-negotiables (print this on your wall)

| # | Rule | The mistake it prevents |
|---|---|---|
| 1 | **Public repo** → no real IPs, cluster names/IDs, node names, kubeconfig contexts, bucket names, PV IDs. Use placeholders + RFC 5737 IPs. Real values → internal runbook. | Leaking infra topology (gitleaks won't catch it — *you* are the gate). |
| 2 | **Secrets** via `infisical run`, never on disk, never read into an AI chat. `.env.example` only. | Credential leaks; secrets stuck in transcripts/history forever. |
| 3 | **Branch** = `<type>/<yourhandle>-<desc>` (e.g. `docs/dilonne-w23-cluster-inventory`). `<dev>` is YOU, not a project code. | PR blocked by `branch-name-check`. |
| 4 | **#OnlyHumanApproves (R-011)** — never push/merge/`tofu apply`/deploy/delete prod without human OK. Migrations: never touch the old box until after soak. | Unapproved or destructive changes. |
| 5 | **Every PR**: real description + #WeOwnVer stamp on new docs + CHANGELOG `[Unreleased]` entry + all review comments addressed. | Thin/unreviewable PRs. |
| 6 | **Search before declaring; prove before verifying.** Check the file exists; run the test before saying "done." | #BadAgent fabrication. |

---

## Toolchain quick reference

| Tool | Use | Don't |
|---|---|---|
| `infisical run -- …` | inject secrets at runtime | write real secrets to `.env` |
| `tofu` (OpenTofu) | IaC plan/apply (apply = human-approved) | `terraform` (we standardize on `tofu`) |
| `copier` | scaffold a new `*-docker/` from `template/` | hand-copy another site's files |
| `doctl` | DigitalOcean CLI (infra devs) | click-ops in the console for repeatable work |
| `pre-commit` | local gitleaks/yamllint/shellcheck gate | `git commit --no-verify` |
| `gh` | PRs, CI status, reviews | — |

---

## When something's unclear

- **Code / repo convention** → `.rules` → `.github/copilot-instructions.md` → `CLAUDE.md`.
- **Business / governance / a CCC-ID question** → `fedarch` PinnedDocs, or **SEEK:META** / ask **@GTM**.
- **Don't invent a WeOwn convention.** If it's not written down, ask — then we'll document it (L-420).

> *Document → Iterate → Automate. Welcome to ♾️ WeOwnNet 🌐.*
