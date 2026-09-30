#!/usr/bin/env python3
"""Read-only DigitalOcean stale-backup monitor.

GET https://api.digitalocean.com/v2/droplets, /volumes, and /snapshots only.
A Droplet or Volume is compliant when its features include "backups", or when
a snapshot dated less than 7 days ago is tied to it (snapshot_ids or the
snapshot list). Otherwise the row is STALE_WARNING or CRITICAL_NO_BACKUP.

Writes BACKUP_STALE_REPORT.md in the current directory and prints the same
Markdown on stdout. The token is never printed and is sent only to
api.digitalocean.com. WEBHOOK_URL, when set, receives the report via
send_webhook_report() and does not receive the DigitalOcean token.

Ubuntu WSL:

    cd /mnt/f/FL/WeOwnAI/ai/scripts/do-backup-monitor
    python3 -m venv .venv
    source .venv/bin/activate
    pip install -r requirements.txt
    cp .env.example .env
    set -a && source .env && set +a
    python3 check_stale_backups.py

Offline check (no token, no network):

    python3 check_stale_backups.py --self-check
"""

from __future__ import annotations

import json
import os
import re
import sys
import time
import urllib.parse
from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone
from pathlib import Path

try:
    import requests
except ImportError:  # pragma: no cover
    requests = None  # type: ignore[assignment]

try:
    from dotenv import load_dotenv
except ImportError:  # pragma: no cover
    load_dotenv = None  # type: ignore[assignment]

API_ROOT = "https://api.digitalocean.com/v2/"
ALLOWED_API_PREFIX = "https://api.digitalocean.com/"
REPORT_FILENAME = "BACKUP_STALE_REPORT.md"
USER_AGENT = "weown-do-backup-monitor/1.0 (read-only)"
ENV_VAR_NAME = re.compile(r"^[A-Z][A-Z0-9_]{1,60}$")
TEAM_LABEL = re.compile(r"^[A-Za-z0-9][A-Za-z0-9 _. -]{0,40}$")
STALE_AFTER = timedelta(days=7)
# Running and powered-off Droplets both keep a disk.
AUDITED_DROPLET_STATUSES = {"active", "off"}
STATUS_ORDER = {
    "CRITICAL_NO_BACKUP": 0,
    "STALE_WARNING": 1,
    "AUDIT_INCOMPLETE": 2,
    "PASS": 3,
}


class DOAPIError(Exception):
    """A DigitalOcean read failed after retries, or the token was refused."""


class DOAuthError(DOAPIError):
    """The token was rejected. Further calls with it will not succeed."""


@dataclass
class TeamAuth:
    label: str
    token: str

    def __repr__(self) -> str:
        return f"TeamAuth(label={self.label!r}, token='<redacted>')"


@dataclass
class Finding:
    team: str
    name: str
    resource_type: str
    address: str
    backup_enabled: bool
    last_snapshot: datetime | None
    days_since: int | None
    status: str


@dataclass
class TeamReport:
    label: str
    findings: list[Finding] = field(default_factory=list)
    warnings: list[str] = field(default_factory=list)
    errors: list[str] = field(default_factory=list)


def assert_digitalocean_url(url: str) -> None:
    parsed = urllib.parse.urlparse(url)
    if parsed.scheme != "https" or parsed.netloc != "api.digitalocean.com":
        raise DOAPIError("refusing to send the token to a non-DigitalOcean host")
    if not url.startswith(ALLOWED_API_PREFIX):
        raise DOAPIError("refusing to send the token to a non-DigitalOcean URL")


def md_cell(value: object) -> str:
    text = "" if value is None else str(value)
    return (
        text.replace("\\", "\\\\")
        .replace("|", "\\|")
        .replace("\r", " ")
        .replace("\n", " ")
    )


def heading_text(value: str) -> str:
    cleaned = " ".join(value.replace("\r", " ").replace("\n", " ").split())
    return cleaned.lstrip("#").strip() or "unnamed"


def parse_time(value: object) -> datetime | None:
    if not isinstance(value, str) or not value.strip():
        return None
    text = value.strip().replace("Z", "+00:00")
    try:
        parsed = datetime.fromisoformat(text)
    except ValueError:
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc)


def backups_enabled(resource: dict) -> bool:
    features = resource.get("features")
    if not isinstance(features, list):
        return False
    return any(str(item).lower() == "backups" for item in features)


def droplet_address(droplet: dict) -> str:
    """Public IPv4 when present, otherwise the Droplet id. Never invents an address."""
    ident = str(droplet.get("id") or "")
    networks = droplet.get("networks") if isinstance(droplet.get("networks"), dict) else {}
    public: list[str] = []
    private: list[str] = []
    for entry in networks.get("v4") or []:
        if not isinstance(entry, dict):
            continue
        ip = str(entry.get("ip_address") or "").strip()
        if not ip:
            continue
        if str(entry.get("type") or "") == "public":
            public.append(ip)
        else:
            private.append(ip)
    chosen = public[0] if public else (private[0] if private else "")
    if chosen and ident:
        return f"{chosen} / {ident}"
    return ident or chosen or "—"


def volume_address(volume: dict) -> str:
    ident = str(volume.get("id") or "")
    return f"— / {ident}" if ident else "—"


def index_snapshots(
    snapshots: list[dict],
) -> tuple[dict[str, datetime], dict[tuple[str, str], list[datetime]]]:
    by_id: dict[str, datetime] = {}
    by_resource: dict[tuple[str, str], list[datetime]] = {}
    for snapshot in snapshots:
        if not isinstance(snapshot, dict):
            continue
        created = parse_time(snapshot.get("created_at"))
        snap_id = str(snapshot.get("id") or "")
        if created is not None and snap_id:
            previous = by_id.get(snap_id)
            if previous is None or created > previous:
                by_id[snap_id] = created
        resource_type = str(snapshot.get("resource_type") or "").lower()
        resource_id = str(snapshot.get("resource_id") or "")
        if created is not None and resource_type and resource_id:
            by_resource.setdefault((resource_type, resource_id), []).append(created)
    return by_id, by_resource


def latest_snapshot(
    *,
    resource_type: str,
    resource_id: str,
    snapshot_ids: object,
    by_id: dict[str, datetime],
    by_resource: dict[tuple[str, str], list[datetime]],
) -> tuple[datetime | None, list[str]]:
    """Newest dated snapshot, plus snapshot ids that have no created_at."""
    candidates = list(by_resource.get((resource_type, resource_id), []))
    undated: list[str] = []
    if isinstance(snapshot_ids, list):
        for raw in snapshot_ids:
            snap_id = str(raw).strip()
            if not snap_id:
                continue
            created = by_id.get(snap_id)
            if created is None:
                undated.append(snap_id)
            else:
                candidates.append(created)
    if not candidates:
        return None, undated
    return max(candidates), undated


def classify(backup_on: bool, latest: datetime | None, now: datetime) -> tuple[str, int | None]:
    """PASS when native backups are on or the newest snapshot is under 7 days."""
    if latest is None:
        days = None
        fresh = False
    else:
        delta = now - latest
        if delta.total_seconds() < 0:
            days = 0
            fresh = True
        else:
            days = int(delta.total_seconds() // 86400)
            fresh = delta < STALE_AFTER
    if backup_on or fresh:
        return "PASS", days
    if latest is None:
        return "CRITICAL_NO_BACKUP", None
    return "STALE_WARNING", days


def _finding(
    team: str,
    name: str,
    resource_type: str,
    address: str,
    resource: dict,
    snapshot_ids: object,
    by_id: dict[str, datetime],
    by_resource: dict[tuple[str, str], list[datetime]],
    now: datetime,
    snapshots_ok: bool,
) -> tuple[Finding, list[str]]:
    notes: list[str] = []
    resource_id = str(resource.get("id") or "")
    latest, undated = latest_snapshot(
        resource_type=resource_type.lower(),
        resource_id=resource_id,
        snapshot_ids=snapshot_ids,
        by_id=by_id,
        by_resource=by_resource,
    )
    enabled = backups_enabled(resource)
    if undated:
        notes.append(
            f"{resource_type} {name}: snapshot id(s) {', '.join(undated)} "
            "have no created_at in GET /v2/snapshots"
        )
    if not snapshots_ok:
        status, days = "AUDIT_INCOMPLETE", None
        latest = None
    else:
        status, days = classify(enabled, latest, now)
    return (
        Finding(
            team=team,
            name=name,
            resource_type=resource_type,
            address=address,
            backup_enabled=enabled,
            last_snapshot=latest,
            days_since=days,
            status=status,
        ),
        notes,
    )


def build_team_report(
    label: str,
    *,
    droplets: list[dict],
    volumes: list[dict],
    snapshots: list[dict],
    now: datetime,
    droplets_ok: bool = True,
    volumes_ok: bool = True,
    snapshots_ok: bool = True,
    errors: list[str] | None = None,
) -> TeamReport:
    report = TeamReport(label=label, errors=list(errors or []))
    if not snapshots_ok:
        report.warnings.append(
            "Snapshot list failed. Rows are AUDIT_INCOMPLETE so a missing list "
            "is not reported as CRITICAL_NO_BACKUP."
        )
    by_id, by_resource = index_snapshots(snapshots if snapshots_ok else [])

    if droplets_ok:
        for droplet in droplets:
            if not isinstance(droplet, dict):
                continue
            status = str(droplet.get("status") or "").lower()
            name = str(droplet.get("name") or droplet.get("id") or "droplet")
            if status and status not in AUDITED_DROPLET_STATUSES:
                report.warnings.append(
                    f"Skipped Droplet {name} (status={status}). "
                    "Audited statuses are active and off."
                )
                continue
            finding, notes = _finding(
                label,
                name,
                "Droplet",
                droplet_address(droplet),
                droplet,
                droplet.get("snapshot_ids"),
                by_id,
                by_resource,
                now,
                snapshots_ok,
            )
            report.findings.append(finding)
            report.warnings.extend(notes)
    if volumes_ok:
        for volume in volumes:
            if not isinstance(volume, dict):
                continue
            name = str(volume.get("name") or volume.get("id") or "volume")
            finding, notes = _finding(
                label,
                name,
                "Volume",
                volume_address(volume),
                volume,
                volume.get("snapshot_ids"),
                by_id,
                by_resource,
                now,
                snapshots_ok,
            )
            report.findings.append(finding)
            report.warnings.extend(notes)
    return report


class DigitalOceanClient:
    """GET-only client. There is no method that writes to DigitalOcean."""

    def __init__(self, auth: TeamAuth) -> None:
        if requests is None:
            raise DOAPIError("install dependencies: pip install -r requirements.txt")
        self.label = auth.label
        self._session = requests.Session()
        self._session.headers.update(
            {
                "Authorization": f"Bearer {auth.token}",
                "Accept": "application/json",
                "User-Agent": USER_AGENT,
            }
        )

    def close(self) -> None:
        self._session.close()

    def get_json(self, url: str, params: dict | None = None) -> dict:
        assert_digitalocean_url(url)
        path = urllib.parse.urlparse(url).path
        delay_seconds = 1.0
        last_error = "request failed"
        for attempt in range(1, 6):
            try:
                response = self._session.get(url, params=params, timeout=(10, 60))
            except requests.RequestException as exc:
                last_error = f"network error ({type(exc).__name__})"
                if attempt == 5:
                    break
                time.sleep(delay_seconds)
                delay_seconds = min(delay_seconds * 2, 60.0)
                continue
            if response.status_code == 401:
                raise DOAuthError(
                    "HTTP 401 — token rejected. Set DIGITALOCEAN_TOKEN to a read-only token."
                )
            if response.status_code == 403:
                raise DOAPIError(f"HTTP 403 — token is missing read scope for {path}")
            if response.status_code == 429 or response.status_code >= 500:
                last_error = f"HTTP {response.status_code} on {path}"
                if attempt == 5:
                    break
                delay_seconds = _retry_delay(response, attempt)
                print(
                    f"[{self.label}] {last_error}; retrying in {delay_seconds:.0f}s "
                    f"(attempt {attempt}/5)",
                    file=sys.stderr,
                )
                time.sleep(delay_seconds)
                continue
            if response.status_code >= 400:
                raise DOAPIError(f"HTTP {response.status_code} on {path}")
            try:
                payload = json.loads(response.text)
            except json.JSONDecodeError as exc:
                raise DOAPIError(f"invalid JSON on {path}") from exc
            if not isinstance(payload, dict):
                raise DOAPIError(f"unexpected JSON on {path}")
            return payload
        raise DOAPIError(last_error)

    def list_all(self, path: str, key: str, params: dict | None = None) -> list:
        url = API_ROOT + path.lstrip("/")
        query: dict | None = dict(params or {})
        query.setdefault("per_page", 200)
        items: list = []
        first = True
        while url:
            shown = "/" + _redact_progress(path.lstrip("/"))
            if first and query:
                extra = {k: v for k, v in query.items() if k != "per_page"}
                if extra:
                    shown += "?" + urllib.parse.urlencode(extra)
            print(
                f"[{self.label}] GET {shown}" if first else f"[{self.label}] GET next page",
                file=sys.stderr,
            )
            payload = self.get_json(url, query if first else None)
            first = False
            query = None
            batch = payload.get(key) or []
            if not isinstance(batch, list):
                raise DOAPIError(f"unexpected list for {key}")
            items.extend(batch)
            pages = (payload.get("links") or {}).get("pages") or {}
            url = str(pages.get("next") or "")
        return items


_PROGRESS_ID = re.compile(
    r"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"
)


def _redact_progress(path: str) -> str:
    """Keep CI logs free of resource ids. This repository is public."""
    return _PROGRESS_ID.sub("<id>", path)


def _retry_delay(response: object, attempt: int) -> float:
    headers = getattr(response, "headers", {}) or {}
    retry_after = headers.get("Retry-After")
    if retry_after:
        try:
            return min(float(retry_after), 120.0)
        except ValueError:
            pass
    reset = headers.get("RateLimit-Reset") or headers.get("ratelimit-reset")
    if reset:
        try:
            wait = float(reset) - time.time()
            if wait > 0:
                return min(wait + 0.5, 120.0)
        except ValueError:
            pass
    return min(float(2**attempt), 60.0)


def collect_team(client: DigitalOceanClient, now: datetime) -> TeamReport:
    errors: list[str] = []

    def grab(what: str, fn):
        try:
            return fn(), True
        except DOAuthError:
            raise
        except DOAPIError as exc:
            errors.append(f"{what}: {exc}")
            return [], False

    droplets, droplets_ok = grab("droplets", lambda: client.list_all("droplets", "droplets"))
    volumes, volumes_ok = grab("volumes", lambda: client.list_all("volumes", "volumes"))
    snapshots: list[dict] = []
    snapshots_ok = True
    for resource_type in ("droplet", "volume"):
        batch, ok = grab(
            f"{resource_type} snapshots",
            lambda resource_type=resource_type: client.list_all(
                "snapshots",
                "snapshots",
                {"resource_type": resource_type},
            ),
        )
        if not ok:
            snapshots_ok = False
        else:
            snapshots.extend(batch)
    return build_team_report(
        client.label,
        droplets=droplets,
        volumes=volumes,
        snapshots=snapshots,
        now=now,
        droplets_ok=droplets_ok,
        volumes_ok=volumes_ok,
        snapshots_ok=snapshots_ok,
        errors=errors,
    )


def _fmt_when(when: datetime | None) -> str:
    if when is None:
        return "—"
    return when.astimezone(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")


def _fmt_days(days: int | None) -> str:
    if days is None:
        return "—"
    return str(days)


def _yes_no(flag: bool) -> str:
    return "yes" if flag else "no"


def noncompliant(findings: list[Finding]) -> list[Finding]:
    return [row for row in findings if row.status in {"CRITICAL_NO_BACKUP", "STALE_WARNING"}]


def render_report(teams: list[TeamReport], generated: str) -> str:
    findings = [row for team in teams for row in team.findings]
    ordered = sorted(
        findings,
        key=lambda row: (STATUS_ORDER.get(row.status, 9), row.team.lower(), row.name.lower()),
    )
    counts = {name: sum(1 for row in findings if row.status == name) for name in STATUS_ORDER}
    partial = any(team.errors for team in teams)
    alert = counts["CRITICAL_NO_BACKUP"] + counts["STALE_WARNING"]
    lines = [
        "<!-- local only: do not commit — contains live resource names and addresses -->",
        "",
        "# DigitalOcean Stale Backup Audit",
        "",
        f"- Generated: {generated}",
        "- Access: read-only `GET /v2/droplets`, `GET /v2/volumes`, `GET /v2/snapshots`",
        "- Window: a snapshot is fresh when its `created_at` is "
        "less than 7 days before this run.",
        "- Droplets in `active` and `off` are audited. "
        "Both keep their disk. Volumes are all audited.",
        "- These list endpoints cover every project in the team.",
        "",
    ]
    if alert:
        lines.append(
            f"**ALERT** — {counts['CRITICAL_NO_BACKUP']} critical, "
            f"{counts['STALE_WARNING']} stale."
        )
    else:
        lines.append("**OK** — every audited resource is compliant.")
    lines.append("")
    if partial or counts["AUDIT_INCOMPLETE"]:
        lines.append(
            "**PARTIAL** — one or more API calls failed. "
            "AUDIT_INCOMPLETE rows are not treated as missing backups."
        )
        lines.append("")
    lines.extend(
        [
            "Compliant means the Droplet `features` array contains `backups`, or a snapshot "
            "from `snapshot_ids` or `GET /v2/snapshots` is less than 7 days old. "
            "Native Droplet backups do not publish a last-run time on these three endpoints, "
            "so a compliant row with backups enabled can show no snapshot date. "
            "A snapshot dated 7 days or older, with backups off, is `STALE_WARNING`. "
            "No backup feature and no dated snapshot is `CRITICAL_NO_BACKUP`.",
            "",
            "| Status | Count |",
            "| --- | ---: |",
            f"| PASS | {counts['PASS']} |",
            f"| STALE_WARNING | {counts['STALE_WARNING']} |",
            f"| CRITICAL_NO_BACKUP | {counts['CRITICAL_NO_BACKUP']} |",
            f"| AUDIT_INCOMPLETE | {counts['AUDIT_INCOMPLETE']} |",
            "",
            "| Team | Resource Name | Resource Type | IP / ID | "
            "Backup Enabled? | Last Snapshot Date | "
            "Days Since Last Backup | Compliance Status |",
            "| --- | --- | --- | --- | --- | --- | ---: | --- |",
        ]
    )
    if not ordered:
        lines.append("| — | — | — | — | — | — | — | — |")
    for row in ordered:
        lines.append(
            "| "
            + " | ".join(
                [
                    md_cell(row.team),
                    md_cell(row.name),
                    md_cell(row.resource_type),
                    md_cell(row.address),
                    _yes_no(row.backup_enabled),
                    _fmt_when(row.last_snapshot),
                    _fmt_days(row.days_since),
                    md_cell(row.status),
                ]
            )
            + " |"
        )
    lines.append("")
    lines.append("## Warnings")
    lines.append("")
    warnings = [note for team in teams for note in team.warnings]
    if warnings:
        for note in warnings:
            lines.append(f"- {md_cell(note)}")
    else:
        lines.append("None.")
    lines.append("")
    lines.append("## API errors")
    lines.append("")
    errors = [f"{team.label}: {note}" for team in teams for note in team.errors]
    if errors:
        for note in errors:
            lines.append(f"- {md_cell(note)}")
    else:
        lines.append("None.")
    lines.append("")
    return "\n".join(lines)


def _is_discord(url: str) -> bool:
    host = urllib.parse.urlparse(url).netloc.lower()
    return host.endswith("discord.com") or host.endswith("discordapp.com")


def _chunks(text: str, limit: int) -> list[str]:
    if len(text) <= limit:
        return [text]
    parts: list[str] = []
    current: list[str] = []
    size = 0
    for block in text.splitlines(keepends=True):
        if len(block) > limit:
            if current:
                parts.append("".join(current))
                current = []
                size = 0
            for start in range(0, len(block), limit):
                parts.append(block[start:start + limit])
            continue
        if size + len(block) > limit and current:
            parts.append("".join(current))
            current = [block]
            size = len(block)
        else:
            current.append(block)
            size += len(block)
    if current:
        parts.append("".join(current))
    return parts


def send_webhook_report(markdown: str, webhook_url: str | None = None) -> bool:
    """POST the Markdown report to a Slack-compatible or Discord webhook.

    The DigitalOcean token is not included. The webhook URL is never printed.
    No-op (returns False) when no URL is configured.
    """
    if requests is None:
        print("webhook skipped: requests is not installed", file=sys.stderr)
        return False
    url = (webhook_url if webhook_url is not None else os.environ.get("WEBHOOK_URL", "")).strip()
    if not url:
        return False
    parsed = urllib.parse.urlparse(url)
    if parsed.scheme != "https" or not parsed.netloc:
        print("webhook skipped: WEBHOOK_URL must be an https URL", file=sys.stderr)
        return False
    style = "discord" if _is_discord(url) else "slack"
    limit = 1800 if style == "discord" else 35000
    chunks = _chunks(markdown, limit)
    for index, chunk in enumerate(chunks, start=1):
        payload = {"content": chunk} if style == "discord" else {"text": chunk}
        try:
            response = requests.post(
                url,
                json=payload,
                timeout=(10, 60),
                headers={"User-Agent": USER_AGENT, "Accept": "application/json"},
            )
        except requests.RequestException as exc:
            print(
                f"webhook failed on part {index}: {type(exc).__name__}",
                file=sys.stderr,
            )
            return False
        if response.status_code >= 300:
            print(
                f"webhook failed on part {index}: HTTP {response.status_code}",
                file=sys.stderr,
            )
            return False
    print(f"webhook delivered ({len(chunks)} part(s))", file=sys.stderr)
    return True


def load_local_env() -> None:
    if load_dotenv is None:
        return
    load_dotenv(Path.cwd() / ".env", override=False)
    load_dotenv(Path(__file__).resolve().parent / ".env", override=False)
    # Shared team tokens live next to the cost reporter. Process env wins.
    load_dotenv(
        Path(__file__).resolve().parent.parent / "do-cost-reporter" / ".env",
        override=False,
    )


def acceptable_label(label: str) -> bool:
    """Team headings may contain spaces. Token-shaped strings are rejected."""
    return bool(TEAM_LABEL.fullmatch(label)) and "dop_v1" not in label.lower()


def parse_extra_team_spec(spec: str) -> list[tuple[str, str]]:
    """Return (label, env var name) pairs. Does not read token values."""
    pairs: list[tuple[str, str]] = []
    for part in spec.split(","):
        entry = part.strip()
        if not entry:
            continue
        if ":" not in entry:
            raise SystemExit(
                "DO_EXTRA_TEAM_TOKENS entries must look like Label:ENV_VAR_NAME"
            )
        team_label, env_name = entry.split(":", 1)
        team_label = team_label.strip()
        env_name = env_name.strip()
        if not acceptable_label(team_label) or not ENV_VAR_NAME.fullmatch(env_name):
            raise SystemExit(
                "DO_EXTRA_TEAM_TOKENS must use a short label and an UPPER_CASE "
                "environment variable name, not a token value."
            )
        pairs.append((team_label, env_name))
    return pairs


def load_teams() -> list[TeamAuth]:
    primary = os.environ.get("DIGITALOCEAN_TOKEN", "").strip()
    if not primary:
        raise SystemExit(
            "Set DIGITALOCEAN_TOKEN "
            "(DigitalOcean -> API -> Tokens, read-only scopes). "
            "Do not pass the token on the command line."
        )
    label = os.environ.get("DIGITALOCEAN_TEAM_NAME", "").strip() or "primary"
    if not acceptable_label(label):
        raise SystemExit(
            "DIGITALOCEAN_TEAM_NAME must be a short label "
            "(letters, numbers, spaces, dot, underscore, hyphen)."
        )
    teams = [TeamAuth(label, primary)]
    extra = os.environ.get("DO_EXTRA_TEAM_TOKENS", "").strip()
    if not extra:
        return teams
    for team_label, env_name in parse_extra_team_spec(extra):
        token = os.environ.get(env_name, "").strip()
        if not token:
            raise SystemExit(
                f"Set {env_name} (named by DO_EXTRA_TEAM_TOKENS for {team_label})."
            )
        teams.append(TeamAuth(team_label, token))
    return teams


def _configure_stdio() -> None:
    for stream in (sys.stdout, sys.stderr):
        reconfigure = getattr(stream, "reconfigure", None)
        if reconfigure is None:
            continue
        try:
            reconfigure(encoding="utf-8", errors="replace")
        except (OSError, ValueError):
            pass


def main(argv: list[str] | None = None) -> int:
    args = list(sys.argv[1:] if argv is None else argv)
    if args == ["--self-check"]:
        self_check()
        print("self-check ok")
        return 0
    if args:
        print("usage: python3 check_stale_backups.py [--self-check]", file=sys.stderr)
        return 2

    _configure_stdio()
    load_local_env()
    if requests is None:
        print("install dependencies: pip install -r requirements.txt", file=sys.stderr)
        return 1
    teams = load_teams()
    now = datetime.now(timezone.utc)
    reports: list[TeamReport] = []
    for auth in teams:
        client = DigitalOceanClient(auth)
        try:
            try:
                reports.append(collect_team(client, now))
            except DOAuthError as exc:
                reports.append(TeamReport(label=auth.label, errors=[str(exc)]))
        finally:
            client.close()

    generated = now.strftime("%Y-%m-%d %H:%M:%S UTC")
    markdown = render_report(reports, generated)
    sys.stdout.write(markdown)
    if not markdown.endswith("\n"):
        sys.stdout.write("\n")
    destination = Path.cwd() / REPORT_FILENAME
    with destination.open("w", encoding="utf-8", newline="\n") as handle:
        handle.write(markdown)
    print(f"wrote {destination}", file=sys.stderr)

    findings = [row for team in reports for row in team.findings]
    bad = noncompliant(findings)
    print(
        "critical={critical} stale={stale} pass={ok} incomplete={inc}".format(
            critical=sum(1 for row in findings if row.status == "CRITICAL_NO_BACKUP"),
            stale=sum(1 for row in findings if row.status == "STALE_WARNING"),
            ok=sum(1 for row in findings if row.status == "PASS"),
            inc=sum(1 for row in findings if row.status == "AUDIT_INCOMPLETE"),
        ),
        file=sys.stderr,
    )

    webhook_set = bool(os.environ.get("WEBHOOK_URL", "").strip())
    webhook_ok = True
    if webhook_set:
        webhook_ok = send_webhook_report(markdown)
    nostr_failed = _publish_nostr(markdown) == "failed"
    incomplete = any(team.errors for team in reports) or any(
        row.status == "AUDIT_INCOMPLETE" for row in findings
    )
    if bad or incomplete or (webhook_set and not webhook_ok) or nostr_failed:
        return 1
    return 0


def _publish_nostr(markdown: str, private_key: str | None = None) -> str:
    scripts_dir = str(Path(__file__).resolve().parent.parent)
    if scripts_dir not in sys.path:
        sys.path.insert(0, scripts_dir)
    from publish_to_buzz import publish_to_buzz

    return publish_to_buzz(markdown, private_key=private_key)


def _iso(when: datetime) -> str:
    return when.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def self_check() -> None:
    assert_digitalocean_url("https://api.digitalocean.com/v2/droplets")
    try:
        assert_digitalocean_url("https://evil.example/v2/droplets")
    except DOAPIError:
        pass
    else:
        raise AssertionError("token URL guard accepted a foreign host")
    assert not hasattr(DigitalOceanClient, "post")

    now = datetime(2026, 10, 1, 12, 0, tzinfo=timezone.utc)
    fresh = now - timedelta(days=3)
    almost = now - timedelta(days=6, hours=23)
    exact = now - timedelta(days=7)
    old = now - timedelta(days=10)
    assert classify(True, old, now) == ("PASS", 10)
    assert classify(False, fresh, now)[0] == "PASS"
    assert classify(False, almost, now)[0] == "PASS"
    assert classify(False, exact, now) == ("STALE_WARNING", 7)
    assert classify(False, None, now) == ("CRITICAL_NO_BACKUP", None)

    report = build_team_report(
        "example-team",
        now=now,
        droplets=[
            {
                "id": 101,
                "name": "web|edge",
                "status": "active",
                "features": ["backups"],
                "snapshot_ids": [],
                "networks": {"v4": [{"ip_address": "203.0.113.10", "type": "public"}]},
            },
            {
                "id": 102,
                "name": "app",
                "status": "off",
                "features": [],
                "snapshot_ids": [900],
                "networks": {"v4": [{"ip_address": "203.0.113.11", "type": "public"}]},
            },
            {
                "id": 103,
                "name": "old-disk",
                "status": "active",
                "features": [],
                "snapshot_ids": [],
                "networks": {"v4": [{"ip_address": "203.0.113.12", "type": "private"}]},
            },
            {
                "id": 104,
                "name": "bare",
                "status": "active",
                "features": [],
                "snapshot_ids": [],
                "networks": {"v4": []},
            },
            {
                "id": 105,
                "name": "provisioning",
                "status": "new",
                "features": [],
                "snapshot_ids": [],
            },
        ],
        volumes=[
            {"id": "vol-fresh", "name": "data", "snapshot_ids": []},
            {"id": "vol-old", "name": "archive", "snapshot_ids": []},
            {"id": "vol-none", "name": "empty", "snapshot_ids": []},
        ],
        snapshots=[
            {
                "id": "900",
                "resource_type": "droplet",
                "resource_id": "999",
                "created_at": _iso(almost),
            },
            {
                "id": "901",
                "resource_type": "droplet",
                "resource_id": "103",
                "created_at": _iso(old),
            },
            {
                "id": "902",
                "resource_type": "volume",
                "resource_id": "vol-fresh",
                "created_at": _iso(fresh),
            },
            {
                "id": "903",
                "resource_type": "volume",
                "resource_id": "vol-old",
                "created_at": _iso(exact),
            },
        ],
    )
    by_name = {row.name: row for row in report.findings}
    assert "provisioning" not in by_name
    assert any("status=new" in note for note in report.warnings)
    assert by_name["web|edge"].status == "PASS"
    assert by_name["web|edge"].backup_enabled is True
    assert by_name["web|edge"].address == "203.0.113.10 / 101"
    assert by_name["app"].status == "PASS"
    assert by_name["app"].days_since == 6
    assert by_name["old-disk"].status == "STALE_WARNING"
    assert by_name["old-disk"].days_since == 10
    assert by_name["old-disk"].address == "203.0.113.12 / 103"
    assert by_name["bare"].status == "CRITICAL_NO_BACKUP"
    assert by_name["bare"].address == "104"
    assert by_name["data"].status == "PASS"
    assert by_name["archive"].status == "STALE_WARNING"
    assert by_name["empty"].status == "CRITICAL_NO_BACKUP"
    assert by_name["empty"].address == "— / vol-none"

    incomplete = build_team_report(
        "example-team",
        now=now,
        droplets=[{"id": 1, "name": "web", "status": "active", "features": []}],
        volumes=[],
        snapshots=[],
        snapshots_ok=False,
        errors=["droplet snapshots: HTTP 403 — token is missing read scope for /v2/snapshots"],
    )
    assert incomplete.findings[0].status == "AUDIT_INCOMPLETE"
    assert incomplete.findings[0].status != "CRITICAL_NO_BACKUP"

    rendered = render_report([report], "2026-10-01 12:00:00 UTC")
    header = (
        "| Team | Resource Name | Resource Type | IP / ID | "
        "Backup Enabled? | Last Snapshot Date | "
        "Days Since Last Backup | Compliance Status |"
    )
    assert header in rendered
    assert "web\\|edge" in rendered
    assert "CRITICAL_NO_BACKUP" in rendered
    assert "STALE_WARNING" in rendered
    assert "**ALERT**" in rendered
    first_data = next(
        line for line in rendered.splitlines()
        if line.startswith("| example-team |")
    )
    assert "CRITICAL_NO_BACKUP" in first_data
    assert "10.0.0.1" not in rendered
    assert "192.168." not in rendered

    green = build_team_report(
        "example-team",
        now=now,
        droplets=[{"id": 1, "name": "web", "status": "active", "features": ["backups"]}],
        volumes=[],
        snapshots=[],
    )
    assert "**OK**" in render_report([green], "2026-10-01 12:00:00 UTC")
    assert parse_extra_team_spec("example-team-b:DO_TOKEN_TEAM_B") == [
        ("example-team-b", "DO_TOKEN_TEAM_B")
    ]
    assert parse_extra_team_spec(
        "We Own Agency:DO_TOKEN_AGENCY,Burned Out Media:DO_TOKEN_BOM"
    ) == [
        ("We Own Agency", "DO_TOKEN_AGENCY"),
        ("Burned Out Media", "DO_TOKEN_BOM"),
    ]
    assert acceptable_label("We Own Labs")
    try:
        parse_extra_team_spec("team:dop_v1_" + ("a" * 16))
    except SystemExit:
        pass
    else:
        raise AssertionError("a token-shaped value was accepted as an env var name")
    assert "".join(_chunks("a\nb\nc\n", 3)) == "a\nb\nc\n"
    assert _redact_progress("volumes/11111111-2222-3333-4444-555555555555") == "volumes/<id>"
    assert _publish_nostr("local report", private_key="") == "skipped"


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except BrokenPipeError:
        raise SystemExit(0)
