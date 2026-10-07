#!/usr/bin/env python3
"""A stand-in for Infisical's Universal Auth API and DigitalOcean's metadata service,
for tests/rotation-check.sh. Synthetic values only; nothing leaves 127.0.0.1.

Answers follow the real service:
  - a failed login: the answer CAPTURED from app.infisical.com on 2026-10-07 (an
    unknown client id): HTTP 401 {"reqId": ..., "statusCode": 401,
    "message": "Invalid credentials", "error": "UnauthorizedError"}
  - the lockout answer, the client-secret create/list/revoke shapes and
    clientSecretPrefix (the first 4 characters): Infisical's source,
    backend/src/services/identity-ua/identity-ua-service.ts and
    backend/src/server/routes/v1/identity-universal-auth-router.ts at df3f6d3f.

State is a JSON file the test edits between runs (modes below), so one server
serves every scenario:
  can_mint     false -> creating a client secret answers 403
  revoke_fails true  -> revoking answers 500
  revoke_lies  true  -> revoking answers 200 "revoked" but leaves the secret active
  locked       true  -> every login answers the 401 lockout message
  lock_after_revoke  -> after the first revoke, `locked` turns on (a lockout mid-run)
usage: stub_infisical.py <port> <state.json>
"""
import base64
import json
import secrets
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

PORT, STATE = int(sys.argv[1]), sys.argv[2]
UA = "/api/v1/auth/universal-auth"


def load():
    with open(STATE) as f:
        return json.load(f)


def save(state):
    with open(STATE, "w") as f:
        json.dump(state, f)


def b64url(obj):
    return base64.urlsafe_b64encode(json.dumps(obj).encode()).decode().rstrip("=")


def sanitized(s):
    return {
        "id": s["id"],
        "createdAt": s["createdAt"],
        "updatedAt": s["createdAt"],
        "description": s.get("description", ""),
        "clientSecretPrefix": s["value"][:4],
        "clientSecretNumUses": 0,
        "clientSecretNumUsesLimit": 0,
        "clientSecretTTL": 0,
        "identityUAId": "ua-1",
        "isClientSecretRevoked": s["revoked"],
    }


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def reply(self, code, body):
        data = body.encode() if isinstance(body, str) else json.dumps(body).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json" if not isinstance(body, str) else "text/plain")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def unauthorized(self, message="Invalid credentials"):
        self.reply(401, {"reqId": "req-stub", "statusCode": 401, "message": message, "error": "UnauthorizedError"})

    def authed(self, st):
        h = self.headers.get("Authorization", "")
        return h.startswith("Bearer ") and h[7:] in st["tokens"]

    def body(self):
        n = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(n) if n else b""
        ctype = self.headers.get("Content-Type", "")
        if ctype.startswith("application/json") and not raw:
            # fastify: FST_ERR_CTP_EMPTY_JSON_BODY
            return None, (400, {"statusCode": 400, "message": "Body cannot be empty when content-type is set to 'application/json'"})
        return (json.loads(raw) if raw else {}), None

    def do_GET(self):
        st = load()
        if self.path == "/metadata/v1/user-data":
            return self.reply(200, st["userdata"]) if st.get("metadata_up", True) else self.reply(503, "down")
        if self.path == f"{UA}/identities/{st['identity']}/client-secrets":
            if not self.authed(st):
                return self.unauthorized("Token missing")
            return self.reply(200, {"clientSecretData": [sanitized(s) for s in st["secrets"]]})
        self.reply(404, {"statusCode": 404, "message": "Not found"})

    def do_POST(self):
        st = load()
        body, err = self.body()
        if err:
            return self.reply(*err)
        if self.path == f"{UA}/login":
            if body.get("clientId") != st["client_id"]:
                return self.unauthorized()
            if st.get("locked"):
                return self.unauthorized("This identity auth method is temporarily locked, please try again later")
            match = [s for s in st["secrets"] if not s["revoked"] and s["value"] == body.get("clientSecret")]
            if not match:
                return self.unauthorized()
            tok = f"{b64url({'alg': 'HS256'})}.{b64url({'identityId': st['identity'], 'clientSecretId': match[0]['id']})}.sig{secrets.token_hex(4)}"
            st["tokens"].append(tok)
            save(st)
            return self.reply(200, {"accessToken": tok, "expiresIn": 7200, "accessTokenMaxTTL": 7200, "tokenType": "Bearer"})
        base = f"{UA}/identities/{st['identity']}/client-secrets"
        if self.path == base:
            if not self.authed(st):
                return self.unauthorized("Token missing")
            if not st.get("can_mint", True):
                return self.reply(403, {"statusCode": 403, "message": "You are not allowed to create on Identity", "error": "PermissionDenied"})
            new = {"id": f"cs-{len(st['secrets']) + 1}", "value": secrets.token_hex(16), "revoked": False,
                   "createdAt": f"2026-10-07T00:00:{len(st['secrets']):02d}Z", "description": body.get("description", "")}
            st["secrets"].append(new)
            save(st)
            return self.reply(200, {"clientSecret": new["value"], "clientSecretData": sanitized(new)})
        if self.path.startswith(base + "/") and self.path.endswith("/revoke"):
            if not self.authed(st):
                return self.unauthorized("Token missing")
            sid = self.path[len(base) + 1:-len("/revoke")]
            hit = [s for s in st["secrets"] if s["id"] == sid]
            if not hit:
                return self.reply(404, {"statusCode": 404, "message": "Client secret not found"})
            if st.get("revoke_fails"):
                return self.reply(500, {"statusCode": 500, "message": "Something went wrong"})
            if not st.get("revoke_lies"):
                hit[0]["revoked"] = True
            if st.get("lock_after_revoke"):
                st["locked"] = True
            save(st)
            return self.reply(200, {"clientSecretData": dict(sanitized(hit[0]), isClientSecretRevoked=True)})
        self.reply(404, {"statusCode": 404, "message": "Not found"})


HTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
