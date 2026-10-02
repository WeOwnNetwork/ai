# ⛔ RETIRED — never deploy this render

**No live droplet runs this render.** Its droplet is off (WeOwnDev/weown-fleet#121, 2026-10-01). The 2026-10-01 registry audit (#112) lists a separate box, `burnedout-xyz-v5`, which this render did not create.

It is not rolled over to the post-Minimus registry (WeOwnDev/weown-fleet#112; see that repo's `mirror/ROLLOVER-PLAN.md`).
`scripts/deploy.sh` refuses to run. Deploying an old render onto a fresh or reused box would bring the app up on empty volumes, with pre-2026-10 images and settings.

Before you revive it, run the identity check from the repo `CLAUDE.md`: the render's `app_dir` and volume names must match what is on the box. Then roll it over with `scripts/registry-rollover.py` and remove this file and the `exit 1` in `scripts/deploy.sh`.

Kept for history only (same pattern as `keycloak-docker/sites/sso.weown.dev/`).
