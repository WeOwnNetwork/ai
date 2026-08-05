# ⛔ RETIRED — never deploy this render

**The live sso droplet (129.212.240.145, sso.weown.id) does NOT run this
render.** It runs the render in [`../sso/`](../sso/), whose project name is
`sso-keycloak` and whose volumes are `sso_keycloak_*`.

This render's project name is `sso` and its volumes are `sso_*`. Deploying it
to the live droplet would bring Keycloak up on **fresh, empty volumes** —
every realm, client, and user silently gone while the container reports
healthy. That is the same failure class that took chat.weown.dev's workspaces
offline on 2026-07-31, and it was one bootstrap-marker check away from
happening here on 2026-08-05 (the deploy failed only because this render
expects `/opt/sso/.bootstrap-complete` and the box has
`/opt/sso_keycloak/.bootstrap-complete`).

**Identity check before deploying ANY rendered site** (this is the rule this
directory exists to teach): the render's `app_dir` and volume-name prefix must
match what is actually on the box —

```bash
ssh <box> 'ls /opt; docker volume ls --format "{{.Name}}"'
grep -n "name: " docker/compose.prod.yaml
```

If they differ, you are holding the wrong render. Stop.

Kept for history only (same tombstone pattern as `anythingllm-docker/sites/s004/`).
Canonical render: [`keycloak-docker/sites/sso/`](../sso/).
