# HANDOFF — Keycloak + Gitea for the WeOwn stack (overnight drive)

> Status: **handoff** · Author: ncimino (via Claude Code) · Date: 2026-07-17
> `main` HEAD at handoff: **`50d298c`** (PR #96 merged — customer dashboard).
> **Operating mode: Nik is ASLEEP.** Drive as far as you can autonomously
> tonight; anything human-gated goes on the morning list (§6), not a blocker to
> stop on. Check things before acting — do not get stuck on one path; if a path
> needs Nik, park it and advance another. Public repo: no secrets, no real IPs
> (RFC 5737), no customer identifiers. Commits: ncimino only, no AI trailers.
> Land work as conformant branch → auto-PR → merge (§5 mechanics).

## 1. Mission

Stand up **Gitea + Keycloak (SSO) for WeOwn** in the `ai` repo pattern —
Jason approved both **in writing** (vault D452). Requirements:

1. **Same principles as Perpetuator Platform internal deployments**, but on the
   WeOwn stack with **Infisical** as the secret store (not OpenBao): IaC-only
   (tofu + ansible, Path C + Layer 2), runtime secret injection (no secrets on
   disk), copier-template form (`<service>-docker/`), hardened per
   SOP-INFRA-012 Phase-A (CIS play + encrypted data volume — both now in
   `anythingllm-docker` as the reference), skinny GPG-encrypted backups,
   OTel observability.
2. **Evaluate Peter/MOT's deployed work for alignment** — his keycloak-SSO
   (PRJ-003), owncloud-oCIS, and smoke-test code are MERGED but he offboarded
   W28 (vault: `Projects/MOT Offboarding Runbook - 2026-07-06.md`). How close
   is what he built to the principles above? What drifts? Are his live
   instances findable/verifiable?
3. **Tonight's concrete goal:** a **local docker-compose proof** that Gitea
   authenticates against Keycloak via OIDC end-to-end (login → Gitea account
   provisioned), using the repo's template
