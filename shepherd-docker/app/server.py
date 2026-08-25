#!/usr/bin/env python3
"""PRJ-435 Shepherd POC HTTP surface.

Stdlib-only listener on SHEPHERD_PORT. Lists persisted traces and reports
whether the mock/offline provider lane is enabled. Does not call live LLM APIs.
"""

from __future__ import annotations

import json
import os
import traceback
from datetime import datetime, timezone
from html import escape
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

PORT = int(os.environ.get("SHEPHERD_PORT", "8080"))
DOMAIN = os.environ.get("SHEPHERD_DOMAIN", "localhost")
MOCK_PROVIDER = os.environ.get("MOCK_PROVIDER", "true").strip().lower() in (
    "1",
    "true",
    "yes",
    "on",
)
LOG_LEVEL = os.environ.get("LOG_LEVEL", "info")
TRACES_DIR = Path(os.environ.get("TRACES_DIR", "/data/traces"))


def _utc_now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _shepherd_info() -> dict:
    info = {"installed": False, "version": None, "import_error": None}
    try:
        import shepherd as sp  # type: ignore

        info["installed"] = True
        info["version"] = getattr(sp, "__version__", "unknown")
    except Exception as exc:  # pragma: no cover - import probe
        info["import_error"] = f"{type(exc).__name__}: {exc}"
    return info


def _list_traces(limit: int = 50) -> list[dict]:
    TRACES_DIR.mkdir(parents=True, exist_ok=True)
    items: list[dict] = []
    try:
        entries = sorted(TRACES_DIR.iterdir(), key=lambda p: p.stat().st_mtime, reverse=True)
    except FileNotFoundError:
        return items
    for path in entries[:limit]:
        try:
            stat = path.stat()
        except OSError:
            continue
        items.append(
            {
                "name": path.name,
                "is_dir": path.is_dir(),
                "bytes": stat.st_size if path.is_file() else None,
                "mtime": datetime.fromtimestamp(stat.st_mtime, tz=timezone.utc).strftime(
                    "%Y-%m-%dT%H:%M:%SZ"
                ),
            }
        )
    return items


def _status_payload() -> dict:
    return {
        "service": "shepherd-poc",
        "ticket": "PRJ-435",
        "ok": True,
        "time": _utc_now(),
        "domain": DOMAIN,
        "port": PORT,
        "mock_provider": MOCK_PROVIDER,
        "log_level": LOG_LEVEL,
        "traces_dir": str(TRACES_DIR),
        "traces": _list_traces(),
        "shepherd": _shepherd_info(),
    }


def _html_page(payload: dict) -> bytes:
    traces_rows = "".join(
        (
            "<tr>"
            f"<td>{escape(str(t.get('name', '')))}</td>"
            f"<td>{'dir' if t.get('is_dir') else 'file'}</td>"
            f"<td>{escape(str(t.get('bytes') if t.get('bytes') is not None else '-'))}</td>"
            f"<td>{escape(str(t.get('mtime', '')))}</td>"
            "</tr>"
        )
        for t in payload.get("traces") or []
    )
    if not traces_rows:
        traces_rows = '<tr><td colspan="4">No traces yet (MOCK_PROVIDER lane is idle until a run is recorded).</td></tr>'
    shepherd = payload.get("shepherd") or {}
    body = f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Shepherd POC — {escape(DOMAIN)}</title>
  <style>
    body {{ font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
           background: #0e1726; color: #e8eef7; margin: 0; padding: 32px; }}
    main {{ max-width: 860px; margin: 0 auto; }}
    h1 {{ font-size: 1.4rem; letter-spacing: -0.02em; }}
    .pill {{ display: inline-block; padding: 2px 10px; border-radius: 999px;
            border: 1px solid rgba(255,255,255,.16); font-size: 0.8rem; }}
    .ok {{ color: #3dd68c; border-color: rgba(61,214,140,.4); }}
    table {{ width: 100%; border-collapse: collapse; margin-top: 16px; }}
    th, td {{ text-align: left; padding: 8px 10px; border-bottom: 1px solid rgba(255,255,255,.1); }}
    code {{ font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace; }}
    a {{ color: #00A3FF; }}
  </style>
</head>
<body>
  <main>
    <p class="pill ok">PRJ-435 · healthy</p>
    <h1>Shepherd POC</h1>
    <p>Domain <code>{escape(DOMAIN)}</code> · mock provider
       <code>{str(payload.get("mock_provider")).lower()}</code> ·
       shepherd-ai <code>{escape(str(shepherd.get("version") or "not-imported"))}</code></p>
    <p>Persisted traces live in <code>{escape(str(payload.get("traces_dir")))}</code>.</p>
    <p><a href="/healthz">/healthz</a> · <a href="/status.json">/status.json</a></p>
    <table>
      <thead><tr><th>Name</th><th>Type</th><th>Bytes</th><th>Modified (UTC)</th></tr></thead>
      <tbody>{traces_rows}</tbody>
    </table>
  </main>
</body>
</html>
"""
    return body.encode("utf-8")


class Handler(BaseHTTPRequestHandler):
    server_version = "shepherd-poc"

    def log_message(self, fmt: str, *args) -> None:  # noqa: A003
        if LOG_LEVEL.lower() in ("debug", "info"):
            sys_stderr = __import__("sys").stderr
            print(f"{_utc_now()} {self.address_string()} {fmt % args}", file=sys_stderr)

    def _send(self, code: int, body: bytes, content_type: str) -> None:
        self.send_response(code)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self) -> None:  # noqa: N802
        path = self.path.split("?", 1)[0]
        try:
            payload = _status_payload()
            if path in ("/healthz", "/health", "/_liveness", "/_readiness"):
                body = json.dumps({"ok": True, "service": "shepherd-poc"}).encode("utf-8")
                self._send(200, body, "application/json; charset=utf-8")
                return
            if path in ("/status.json", "/status"):
                body = json.dumps(payload, indent=2).encode("utf-8")
                self._send(200, body, "application/json; charset=utf-8")
                return
            if path in ("/", "/index.html"):
                self._send(200, _html_page(payload), "text/html; charset=utf-8")
                return
            self._send(404, b'{"ok":false,"error":"not found"}\n', "application/json; charset=utf-8")
        except Exception:
            err = traceback.format_exc().encode("utf-8")
            if LOG_LEVEL.lower() == "debug":
                print(err.decode("utf-8"), file=__import__("sys").stderr)
            self._send(500, b'{"ok":false,"error":"internal"}\n', "application/json; charset=utf-8")


def main() -> None:
    TRACES_DIR.mkdir(parents=True, exist_ok=True)
    marker = TRACES_DIR / "README.txt"
    if not marker.exists():
        marker.write_text(
            "Shepherd POC traces volume (PRJ-435).\n"
            "MOCK_PROVIDER runs do not call live LLM APIs.\n",
            encoding="utf-8",
        )
    httpd = ThreadingHTTPServer(("0.0.0.0", PORT), Handler)
    print(
        f"{_utc_now()} shepherd-poc listening on 0.0.0.0:{PORT} "
        f"domain={DOMAIN} mock={MOCK_PROVIDER}",
        flush=True,
    )
    httpd.serve_forever()


if __name__ == "__main__":
    main()
