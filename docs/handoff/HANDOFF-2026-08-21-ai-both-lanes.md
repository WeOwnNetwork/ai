# ai worker hand-off — both lanes (2026-08-21)

Fresh-agent continuation pointer for the standing **two-stream** `ai` worker: **(A) keycloak / Gitea
/ SSO** and **(B) AnythingLLM / WeOwn.Chat / billing**. Supersedes
[`HANDOFF-2026-08-09-ai-both-lanes.md`](HANDOFF-2026-08-09-ai-both-lanes.md) — read this one first;
the older docs stay as history and remain correct on their landmines.

**Issues are DISABLED on this repo.** The durable record is the WeOwn vault board
(`Projects/Keycloak-Gitea Rebuild - Open Items Board - 2026-07-18.md`), and the full narrative
hand-off — never-started work, fenced decisions, cannot-infer facts, and the kickoff seed — is the
newest addendum in `notes-weown/Projects/ai Repo - Thread Hand-offs.md`
(engagement custody: WeOwn substance does not go in the Perpetuator vault).

**Start a successor with:** `/worker ai`

---

## State at this hand-off

| Repo | Branch / state |
| --- | --- |
| `WeOwnNetwork/ai` (this repo, PUBLIC) | `main` carries the merged **#179** doc restructure; `docs/design/DESIGN-*.md` + `docs/requirements/REQUIREMENTS-*.md`. Working tree clean except the deliberate untracked items below. |
| `WeOwnCloud/openbao` | 🔴 `feature/nik-openbao-wave0` @ `1b85aab` is **8 commits ahead of a main that merged Wave 0 from a different branch** (`cto/openbao-wave0`, PR #1). Clean merge, strict superset. **Needs PR #2 — Nik opens it.** |
| `WeOwnDev/weown-fleet` | fully merged (#22); safe to fast-forward. |

## The three rules a fresh worker most often breaks here

1. ⛔ **This is a CLIENT repo — the fleet's `merge/<agent>` rolling-branch default is REJECTED.**
   The ruleset enforces `^(feature|fix|docs|hotfix)/<dev>-<desc>`; a `merge/<agent>` PR can never
   merge. Read this repo's [`CLAUDE.md`](../../CLAUDE.md) before working or dispatching in it.
2. ⛔ **No Perpetuator artifact taxonomy in WeOwn repos** — no `CAP-`/`RP-` names, no
   `north_star_goal:`/`okr:` frontmatter, no OKR/North-Star trace lines, no `PRJ-*`/`A###` ids.
   (Nik `#badagent` strike 2026-08-19; remediated and merged in #179 — keep it that way.)
3. ⛔ **Never deploy `keycloak-docker/sites/sso.weown.dev/`** — it declares volumes `sso_*` while the
   live box runs `sso_keycloak_*`, so deploying it starts Keycloak on **empty volumes: every realm,
   client and user silently gone behind green healthchecks.** The canonical render is
   `keycloak-docker/sites/sso/`. Keycloak/gitea renders are **patched in place, never re-rendered.**

## Environment facts a fresh agent cannot infer

- **`WEOWN_BOT_PAT` is dead** → `auto-pr-to-main.yml` fails at checkout on every push, so **every PR
  is opened and merged by hand.** Auto-merge is disabled repo-wide.
- Commits author as **`ncimino <nik@weown.net>`**, no AI co-author trailer (G8: never a Capital
  Copilot address on WeOwn artifacts).
- This seat holds **no forge API token**; the mcp Gitea gateway 404s on `WeOwnCloud` (private repo).
  PR opens are therefore always a Nik hand-over with a compare URL.
- **Deliberately untracked, do not clean away:** the 7 operator helper scripts in
  `keycloak-docker/sites/sso/scripts/*.sh` and the rendered `gitea-docker/sites/`.

## Where the work actually is

Everything actionable — the P0, the Nik/Jason-gated queue, the never-started tier, and the
priority-ranked kickoff seed — is in the vault addendum named at the top of this file. This document
is a pointer by design; it does not duplicate that content.
