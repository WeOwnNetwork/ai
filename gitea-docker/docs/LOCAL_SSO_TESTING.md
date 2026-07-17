# Local Gitea ↔ Keycloak OIDC testing — landmines

Field notes from the first local end-to-end SSO validation of this template
(2026-07-17). These four cost the most time; check them before debugging
anything else.

## 1. `INSTALL_LOCK` is mandatory for env-only config

Gitea configured purely via `GITEA__*` environment variables still considers
itself *uninstalled* until `GITEA__security__INSTALL_LOCK=true` is set. Without
it, every `gitea admin …` CLI call (including `auth add-oauth`) dies with:

```text
Unable to load config file for a installed Gitea instance … or run "gitea web"
```

Both compose files in this template set it; keep it if you fork.

## 2. The issuer URL must resolve identically in-container and in-browser

The Gitea *server* fetches the OIDC discovery/token endpoints; the *browser*
follows the authorization endpoint from the same document. Both hosts must
resolve the same issuer.

- `extra_hosts: ["localhost:host-gateway"]` does **not** work — the image's
  built-in `127.0.0.1 localhost` entry wins.
- What works locally: use a host both sides resolve identically — e.g. the
  workstation's LAN IP (`ipconfig getifaddr en0`) as the discovery URL host.
- In production this is a non-issue: the public `https://sso.…` domain is the
  issuer everywhere.

## 3. Keycloak realms reject non-localhost HTTP (`sslRequired=external`)

A fresh realm defaults to `sslRequired=external`, so discovery via a LAN IP
over HTTP returns **403 `{"error":"invalid_request","error_description":"HTTPS
required"}`**. For a throwaway local realm only:

```bash
kcadm.sh update realms/<realm> -s sslRequired=NONE
```

Never relax this on a live realm — production issuers are HTTPS and unaffected.

## 4. Request `offline_access` via scopes (refresh token)

Gitea needs a refresh token, or newly auto-registered SSO users are created
with `prohibit_login=true`. Keycloak 24's kcadm PUT to
`clients/<id>/default-client-scopes/<scope-id>` can 404 — the reliable path is
leaving `offline_access` as an **optional** client scope and having Gitea
request it explicitly:

```bash
gitea admin auth add-oauth … --scopes "openid email profile offline_access"
```

(`email` is also mandatory — without it auto-registration fails with
"missing fields: email".)

## Bonus: auth-source name is case-sensitive

The Keycloak client's redirect URI embeds the Gitea auth-source name:
`…/user/oauth2/Keycloak/callback` ↔ `--name Keycloak`. A case mismatch breaks
the callback with no obvious error.
