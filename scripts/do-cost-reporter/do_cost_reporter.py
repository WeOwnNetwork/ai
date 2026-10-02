#!/usr/bin/env python3
"""Read-only DigitalOcean monthly cost reporter.

Queries https://api.digitalocean.com/v2/ with GET requests only, groups
list-price run-rate by project and by tag, prints Markdown on stdout, and
writes DO_MONTHLY_COST_REPORT.md in the current directory.

The API token is read from DIGITALOCEAN_TOKEN. It is never printed, never
accepted as a command argument, and never sent to any host other than
api.digitalocean.com. An optional webhook (WEBHOOK_URL) is a separate POST
and does not carry the DigitalOcean token.

Ubuntu WSL:

    cd /path/to/ai/scripts/do-cost-reporter
    python3 -m venv .venv
    source .venv/bin/activate
    pip install -r requirements.txt
    # export DIGITALOCEAN_TOKEN in this shell. Do not write it to a file.
    python3 do_cost_reporter.py

Offline pricing check (no token, no network):

    python3 do_cost_reporter.py --self-check
"""

from __future__ import annotations

import json
import os
import re
import sys
import time
import urllib.parse
from dataclasses import dataclass, field
from datetime import datetime, timezone
from decimal import Decimal, InvalidOperation, ROUND_DOWN, ROUND_HALF_UP
from pathlib import Path

try:
    import requests
except ImportError:  # pragma: no cover - exercised only when deps are missing
    requests = None  # type: ignore[assignment]

API_ROOT = "https://api.digitalocean.com/v2/"
ALLOWED_API_PREFIX = "https://api.digitalocean.com/"
REPORT_FILENAME = "DO_MONTHLY_COST_REPORT.md"
UNALLOCATED = "Unallocated / Shared"
USER_AGENT = "weown-do-cost-reporter/1.0 (read-only)"
# Extra-team tokens are named by UPPER_CASE env vars. A pasted token
# (dop_v1_...) must fail this pattern so the value is never echoed.
ENV_VAR_NAME = re.compile(r"^[A-Z][A-Z0-9_]{1,60}$")
TEAM_LABEL = re.compile(r"^[A-Za-z0-9][A-Za-z0-9 _.-]{0,40}$")
PROJECT_ID = re.compile(r"^[A-Za-z0-9-]{1,64}$")

# Published list prices. Droplet and Kubernetes node prices come from the API.
# Volumes: $0.10/GiB-month (this task; also $10 per 100 GiB on DO's volume page).
# Load balancers: https://docs.digitalocean.com/products/networking/load-balancers/details/pricing/
#   regional HTTP $12/node, regional network $15/node, global $15 base.
#   Legacy size slugs: lb-small=1 node, lb-medium=3, lb-large=6.
# Snapshots: https://docs.digitalocean.com/products/snapshots/details/pricing/
#   $0.06/GiB-month, $0.01 minimum.
VOLUME_USD_PER_GIB = Decimal("0.10")
SNAPSHOT_USD_PER_GIB = Decimal("0.06")
SNAPSHOT_MINIMUM = Decimal("0.01")
LB_HTTP_PER_NODE = Decimal("12.00")
LB_NETWORK_PER_NODE = Decimal("15.00")
LB_GLOBAL_BASE = Decimal("15.00")
LEGACY_LB_NODES = {"lb-small": 1, "lb-medium": 3, "lb-large": 6}
HTTP_LB_PROTOCOLS = {"http", "https", "http2", "http3"}
NETWORK_LB_PROTOCOLS = {"tcp", "udp"}
KIND_ORDER = ("Droplet", "Kubernetes", "Volume", "Load balancer", "Snapshot")
CENT = Decimal("0.01")


class DOAPIError(Exception):
    """A DigitalOcean read failed after retries, or the token was refused."""


class DOAuthError(DOAPIError):
    """The token was rejected. Further calls with it will not succeed."""


@dataclass
class Line:
    kind: str
    name: str
    region: str
    detail: str
    tags: tuple[str, ...]
    monthly: Decimal | None
    project: str


@dataclass
class TeamReport:
    label: str
    lines: list[Line] = field(default_factory=list)
    warnings: list[str] = field(default_factory=list)
    errors: list[str] = field(default_factory=list)
    empty_projects: int = 0
    cluster_count: int = 0
    stateful_unbacked: int = 0


@dataclass
class TeamAuth:
    label: str
    token: str
    token_env: str = "DIGITALOCEAN_TOKEN"

    def __repr__(self) -> str:
        return f"TeamAuth(label={self.label!r}, token='<redacted>')"


def money(value: Decimal | int | str) -> Decimal:
    return Decimal(value).quantize(CENT, rounding=ROUND_HALF_UP)


def as_decimal(value: object) -> Decimal | None:
    if value is None or isinstance(value, bool) or value == "":
        return None
    try:
        return Decimal(str(value))
    except (InvalidOperation, ValueError):
        return None


def as_int(value: object) -> int | None:
    if isinstance(value, bool) or value is None:
        return None
    if isinstance(value, int):
        return value
    if isinstance(value, Decimal) and value == value.to_integral_value():
        return int(value)
    if isinstance(value, str) and value.isdigit():
        return int(value)
    return None


def fmt_money(amount: Decimal | None) -> str:
    if amount is None:
        return "n/a"
    quantized = money(amount)
    sign = "-" if quantized < 0 else ""
    return f"{sign}${abs(quantized):,.2f}"


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


def split_even(amount: Decimal, parts: int) -> list[Decimal]:
    """Split a cent-rounded amount so the shares add back to the original."""
    total = money(amount)
    if parts <= 1:
        return [total]
    base = (total / parts).quantize(CENT, rounding=ROUND_DOWN)
    shares = [base for _ in range(parts)]
    leftover_cents = int(((total - base * parts) / CENT).to_integral_value())
    for index in range(leftover_cents):
        shares[index % parts] += CENT
    return shares


def assert_digitalocean_url(url: str) -> None:
    """The bearer token may only be sent to the official DigitalOcean API."""
    parsed = urllib.parse.urlparse(url)
    if parsed.scheme != "https" or parsed.netloc != "api.digitalocean.com":
        raise DOAPIError("refusing to send the token to a non-DigitalOcean host")
    if not url.startswith(ALLOWED_API_PREFIX):
        raise DOAPIError("refusing to send the token to a non-DigitalOcean URL")


def region_slug(value: object) -> str:
    if isinstance(value, str):
        return value
    if isinstance(value, dict):
        slug = value.get("slug") or value.get("name") or ""
        return str(slug)
    if isinstance(value, list):
        parts = [region_slug(item) for item in value]
        return ", ".join(part for part in parts if part)
    return ""


def urn_to_key(urn: str) -> str | None:
    parts = urn.strip().split(":")
    if len(parts) < 3 or parts[0] != "do":
        return None
    kind = parts[1].lower()
    aliases = {
        "k8s": "kubernetes",
        "lb": "loadbalancer",
        "image": "snapshot",
    }
    kind = aliases.get(kind, kind)
    ident = parts[2].strip()
    if not ident:
        return None
    return f"{kind}:{ident}"


def resource_key(kind: str, ident: object) -> str:
    return f"{kind}:{ident}"


def tag_tuple(raw: object) -> tuple[str, ...]:
    if not isinstance(raw, list):
        return ()
    tags = []
    for item in raw:
        text = str(item).strip()
        if text and text not in tags:
            tags.append(text)
    return tuple(tags)


def display_tags(tags: tuple[str, ...]) -> tuple[str, ...]:
    return tags if tags else (UNALLOCATED,)


def sort_label(label: str) -> tuple[int, str]:
    if label == UNALLOCATED:
        return (1, "")
    return (0, label.lower())


def droplet_unit_price(droplet: dict, size_prices: dict[str, Decimal]) -> Decimal | None:
    size = droplet.get("size")
    if isinstance(size, dict):
        price = as_decimal(size.get("price_monthly"))
        if price is not None:
            return money(price)
        slug = str(size.get("slug") or droplet.get("size_slug") or "")
    else:
        slug = str(size or droplet.get("size_slug") or "")
    catalog = size_prices.get(slug)
    if catalog is None:
        return None
    return money(catalog)


def infer_lb_type(lb: dict) -> str:
    explicit = str(lb.get("type") or "").upper()
    if explicit in {"REGIONAL", "REGIONAL_NETWORK", "GLOBAL"}:
        return explicit
    protocols = set()
    for rule in lb.get("forwarding_rules") or []:
        if isinstance(rule, dict):
            protocols.add(str(rule.get("entry_protocol") or "").lower())
    protocols.discard("")
    if protocols and protocols <= NETWORK_LB_PROTOCOLS:
        return "REGIONAL_NETWORK"
    return "REGIONAL"


def lb_node_count(lb: dict) -> int:
    unit = as_int(lb.get("size_unit"))
    if unit is not None and unit >= 1:
        return unit
    size = str(lb.get("size") or "").lower()
    return LEGACY_LB_NODES.get(size, 1)


def load_balancer_monthly(lb: dict) -> tuple[Decimal, str]:
    kind = infer_lb_type(lb)
    nodes = lb_node_count(lb)
    if kind == "GLOBAL":
        return (
            money(LB_GLOBAL_BASE),
            "global base $15 (request and transfer overage not estimated)",
        )
    if kind == "REGIONAL_NETWORK":
        return (
            money(LB_NETWORK_PER_NODE * nodes),
            f"regional network {nodes} x $15",
        )
    return money(LB_HTTP_PER_NODE * nodes), f"regional HTTP {nodes} x $12"


def volume_monthly(volume: dict) -> Decimal | None:
    size = as_decimal(volume.get("size_gigabytes"))
    if size is None:
        return None
    return money(size * VOLUME_USD_PER_GIB)


def snapshot_monthly(snapshot: dict) -> Decimal | None:
    size = as_decimal(snapshot.get("size_gigabytes"))
    if size is None:
        return None
    if size <= 0:
        return Decimal("0.00")
    raw = money(size * SNAPSHOT_USD_PER_GIB)
    if raw < SNAPSHOT_MINIMUM:
        return SNAPSHOT_MINIMUM
    return raw


def size_catalog(sizes: list[dict]) -> dict[str, Decimal]:
    catalog: dict[str, Decimal] = {}
    for size in sizes:
        slug = str(size.get("slug") or "")
        price = as_decimal(size.get("price_monthly"))
        if slug and price is not None:
            catalog[slug] = money(price)
    return catalog


def project_labels(projects: list[dict]) -> dict[str, str]:
    """Map project id to a unique display name."""
    labels: dict[str, str] = {}
    seen: set[str] = set()
    for project in projects:
        pid = str(project.get("id") or "")
        name = heading_text(str(project.get("name") or "unnamed project"))
        if name in seen:
            suffix = pid[:8]
            name = f"{name} ({suffix})" if suffix else f"{name} (duplicate)"
        seen.add(name)
        if pid:
            labels[pid] = name
    return labels


def index_project_resources(
    labels: dict[str, str],
    urns_by_project_id: dict[str, list[str]],
) -> tuple[dict[str, str], list[str]]:
    """Map resource key -> project name. The first project keeps the resource."""
    index: dict[str, str] = {}
    notes: list[str] = []
    for pid, urns in urns_by_project_id.items():
        name = labels.get(pid, "unnamed project")
        for urn in urns:
            key = urn_to_key(str(urn))
            if not key:
                continue
            previous = index.get(key)
            if previous and previous != name:
                notes.append(
                    f"{key} is listed in {previous!r} and {name!r}; counted under {previous!r}"
                )
                continue
            index[key] = name
    return index, notes


def pool_monthly(
    pool: dict,
    droplets_by_id: dict[str, dict],
    size_prices: dict[str, Decimal],
) -> tuple[Decimal | None, str, set[str]]:
    """Bill a node pool at its current count. Return worker droplet ids to exclude."""
    slug = str(pool.get("size") or "")
    count = as_int(pool.get("count")) or 0
    nodes = pool.get("nodes") if isinstance(pool.get("nodes"), list) else []
    worker_ids: set[str] = set()
    matched_prices: list[Decimal] = []
    for node in nodes:
        if not isinstance(node, dict):
            continue
        droplet_id = str(node.get("droplet_id") or "")
        if not droplet_id:
            continue
        worker_ids.add(droplet_id)
        droplet = droplets_by_id.get(droplet_id)
        if not droplet:
            continue
        price = droplet_unit_price(droplet, size_prices)
        if price is not None:
            matched_prices.append(price)

    autoscale = ""
    if pool.get("auto_scale"):
        minimum = as_int(pool.get("min_nodes"))
        maximum = as_int(pool.get("max_nodes"))
        autoscale = f", autoscale {minimum}-{maximum}, billed at current count {count}"

    detail = f"{count} x {slug or 'unknown size'}{autoscale}"
    if count <= 0:
        return Decimal("0.00"), detail, worker_ids

    if matched_prices:
        unit = money(sum(matched_prices, Decimal("0")) / len(matched_prices))
    else:
        unit = size_prices.get(slug)

    if unit is None:
        return None, detail, worker_ids
    return money(unit * count), detail, worker_ids


def build_team_report(
    label: str,
    *,
    sizes: list[dict],
    projects: list[dict],
    urns_by_project_id: dict[str, list[str]],
    droplets: list[dict],
    clusters: list[dict],
    volumes: list[dict],
    load_balancers: list[dict],
    snapshots: list[dict],
    errors: list[str] | None = None,
) -> TeamReport:
    report = TeamReport(label=label, errors=list(errors or []))
    prices = size_catalog(sizes)
    labels = project_labels(projects)
    project_of, notes = index_project_resources(labels, urns_by_project_id)
    report.warnings.extend(notes)

    droplets_by_id = {str(item.get("id")): item for item in droplets if item.get("id") is not None}
    worker_ids: set[str] = set()
    attached = _volume_attached_ids(volumes)
    report.cluster_count = sum(1 for cluster in clusters if isinstance(cluster, dict))

    for cluster in clusters:
        cluster_name = str(cluster.get("name") or cluster.get("id") or "kubernetes")
        cluster_tags = tag_tuple(cluster.get("tags"))
        cluster_region = region_slug(cluster.get("region"))
        project = project_of.get(resource_key("kubernetes", cluster.get("id")), UNALLOCATED)
        pools = cluster.get("node_pools") if isinstance(cluster.get("node_pools"), list) else []
        if not pools:
            report.lines.append(
                Line(
                    "Kubernetes",
                    cluster_name,
                    cluster_region,
                    "no node pools",
                    cluster_tags,
                    Decimal("0.00"),
                    project,
                )
            )
            continue
        for pool in pools:
            if not isinstance(pool, dict):
                continue
            monthly, detail, used = pool_monthly(pool, droplets_by_id, prices)
            worker_ids.update(used)
            pool_name = str(pool.get("name") or "pool")
            if monthly is None:
                report.warnings.append(
                    f"Kubernetes pool {cluster_name}/{pool_name}: "
                    f"no price for size {pool.get('size')!s}"
                )
            if (as_int(pool.get("count")) or 0) <= 0 and used:
                report.warnings.append(
                    f"Kubernetes pool {cluster_name}/{pool_name}: count is 0 while "
                    f"{len(used)} worker droplet(s) are still listed; omitted from Droplets "
                    "and not added while the pool count is 0"
                )
            report.lines.append(
                Line(
                    "Kubernetes",
                    f"{cluster_name} / {pool_name}",
                    cluster_region,
                    detail,
                    cluster_tags,
                    monthly,
                    project,
                )
            )

    for droplet in droplets:
        droplet_id = str(droplet.get("id") or "")
        if droplet_id and droplet_id in worker_ids:
            continue
        if _missing_backup_policy(droplet, droplet_id, attached):
            report.stateful_unbacked += 1
        price = droplet_unit_price(droplet, prices)
        if price is None:
            report.warnings.append(
                f"Droplet {droplet.get('name') or droplet_id}: size price missing from the API"
            )
        size = droplet.get("size")
        slug = ""
        if isinstance(size, dict):
            slug = str(size.get("slug") or "")
        elif size:
            slug = str(size)
        slug = slug or str(droplet.get("size_slug") or "")
        status = str(droplet.get("status") or "")
        detail = " · ".join(part for part in (slug, f"status={status}" if status else "") if part)
        report.lines.append(
            Line(
                "Droplet",
                str(droplet.get("name") or droplet_id or "droplet"),
                region_slug(droplet.get("region")),
                detail,
                tag_tuple(droplet.get("tags")),
                price,
                project_of.get(resource_key("droplet", droplet.get("id")), UNALLOCATED),
            )
        )

    for volume in volumes:
        price = volume_monthly(volume)
        if price is None:
            report.warnings.append(
                f"Volume {volume.get('name') or volume.get('id')}: size_gigabytes missing"
            )
        size = volume.get("size_gigabytes")
        report.lines.append(
            Line(
                "Volume",
                str(volume.get("name") or volume.get("id") or "volume"),
                region_slug(volume.get("region")),
                f"{size} GiB x $0.10" if size is not None else "size unknown",
                tag_tuple(volume.get("tags")),
                price,
                project_of.get(resource_key("volume", volume.get("id")), UNALLOCATED),
            )
        )

    for lb in load_balancers:
        price, detail = load_balancer_monthly(lb)
        report.lines.append(
            Line(
                "Load balancer",
                str(lb.get("name") or lb.get("id") or "load balancer"),
                region_slug(lb.get("region")),
                detail,
                tag_tuple(lb.get("tags")),
                price,
                project_of.get(resource_key("loadbalancer", lb.get("id")), UNALLOCATED),
            )
        )

    seen_snapshots: set[str] = set()
    for snapshot in snapshots:
        snap_id = str(snapshot.get("id") or "")
        if snap_id and snap_id in seen_snapshots:
            continue
        if snap_id:
            seen_snapshots.add(snap_id)
        price = snapshot_monthly(snapshot)
        if price is None:
            report.warnings.append(
                f"Snapshot {snapshot.get('name') or snap_id}: size_gigabytes missing"
            )
        resource_type = str(snapshot.get("resource_type") or "snapshot")
        size = snapshot.get("size_gigabytes")
        detail = f"{resource_type} snapshot"
        if size is not None:
            detail = f"{detail}, {size} GiB x $0.06 (min $0.01)"
        report.lines.append(
            Line(
                "Snapshot",
                str(snapshot.get("name") or snap_id or "snapshot"),
                region_slug(snapshot.get("regions")),
                detail,
                tag_tuple(snapshot.get("tags")),
                price,
                project_of.get(resource_key("snapshot", snapshot.get("id")), UNALLOCATED),
            )
        )

    named_projects = set(labels.values())
    used_projects = {line.project for line in report.lines}
    report.empty_projects = len(named_projects - used_projects)
    return report


class DigitalOceanClient:
    """GET-only client. There is no method that writes to DigitalOcean."""

    def __init__(self, auth: TeamAuth) -> None:
        if requests is None:
            raise DOAPIError("install dependencies: pip install -r requirements.txt")
        self.label = auth.label
        self.token_env = auth.token_env
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
                    f"HTTP 401 — token rejected. Set {self.token_env} to a read-only token."
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
                payload = json.loads(response.text, parse_float=Decimal)
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
            shown = _redact_progress(path.lstrip("/"))
            print(
                f"[{self.label}] GET /{shown}" if first else f"[{self.label}] GET next page",
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
    """Keep CI logs free of project ids. This repository is public."""
    return _PROGRESS_ID.sub("<id>", path)


def _retry_delay(response: object, attempt: int) -> float:
    headers = getattr(response, "headers", {}) or {}
    retry_after = headers.get("Retry-After")
    if retry_after:
        try:
            return min(float(retry_after), 120.0)
        except ValueError:
            # An HTTP-date or garbage Retry-After: fall through to RateLimit-Reset,
            # then to exponential backoff.
            pass
    reset = headers.get("RateLimit-Reset") or headers.get("ratelimit-reset")
    if reset:
        try:
            wait = float(reset) - time.time()
            if wait > 0:
                return min(wait + 0.5, 120.0)
        except ValueError:
            # A malformed reset time: fall back to exponential backoff below.
            pass
    return min(float(2**attempt), 60.0)


def collect_team(client: DigitalOceanClient) -> TeamReport:
    errors: list[str] = []

    def grab(what: str, fn, default):
        try:
            return fn()
        except DOAuthError:
            raise
        except DOAPIError as exc:
            errors.append(f"{what}: {exc}")
            return default

    sizes = grab("sizes", lambda: client.list_all("sizes", "sizes"), [])
    projects = grab("projects", lambda: client.list_all("projects", "projects"), [])
    urns: dict[str, list[str]] = {}
    for project in projects:
        pid = str(project.get("id") or "")
        name = heading_text(str(project.get("name") or "unnamed project"))
        if not PROJECT_ID.fullmatch(pid):
            errors.append(f"projects: skipped {name!r} because its id was not usable")
            continue
        resources = grab(
            f"project {name}",
            lambda pid=pid: client.list_all(f"projects/{pid}/resources", "resources"),
            None,
        )
        if resources is None:
            errors.append(
                f"project {name}: resource list failed; its resources may show under {UNALLOCATED}"
            )
            continue
        urns[pid] = [
            str(item.get("urn"))
            for item in resources
            if isinstance(item, dict) and item.get("urn")
        ]

    droplets = grab("droplets", lambda: client.list_all("droplets", "droplets"), [])
    clusters = grab(
        "kubernetes",
        lambda: client.list_all("kubernetes/clusters", "kubernetes_clusters"),
        [],
    )
    volumes = grab("volumes", lambda: client.list_all("volumes", "volumes"), [])
    load_balancers = grab(
        "load balancers",
        lambda: client.list_all("load_balancers", "load_balancers"),
        [],
    )
    snapshots: list[dict] = []
    for resource_type in ("droplet", "volume"):
        batch = grab(
            f"{resource_type} snapshots",
            lambda resource_type=resource_type: client.list_all(
                "snapshots",
                "snapshots",
                {"resource_type": resource_type},
            ),
            None,
        )
        if batch is not None:
            snapshots.extend(batch)

    return build_team_report(
        client.label,
        sizes=sizes,
        projects=projects,
        urns_by_project_id=urns,
        droplets=droplets,
        clusters=clusters,
        volumes=volumes,
        load_balancers=load_balancers,
        snapshots=snapshots,
        errors=errors,
    )


def _volume_attached_ids(volumes: list[dict]) -> set[str]:
    attached: set[str] = set()
    for volume in volumes:
        raw = volume.get("droplet_ids")
        if not isinstance(raw, list):
            continue
        for item in raw:
            if item is not None:
                attached.add(str(item))
    return attached


def _missing_backup_policy(droplet: dict, droplet_id: str, attached: set[str]) -> bool:
    """A stateful droplet has a volume and no DigitalOcean backup feature."""
    raw_volumes = droplet.get("volume_ids")
    own: list[str] = []
    if isinstance(raw_volumes, list):
        own = [str(item) for item in raw_volumes if item is not None]
    if droplet_id not in attached and not own:
        return False
    features = droplet.get("features")
    if isinstance(features, list) and "backups" in features:
        return False
    return True


def _plural(count: int, singular: str, plural: str | None = None) -> str:
    word = singular if count == 1 else (plural or f"{singular}s")
    return f"{count} {word}"


def _summary_month(generated: str) -> str:
    try:
        when = datetime.strptime(generated[:10], "%Y-%m-%d")
    except ValueError:
        return generated
    return when.strftime("%B %Y")


def buzz_summary(teams: list[TeamReport], generated: str) -> str:
    """Short channel note. Resource names stay in the local report file."""
    all_lines = [line for team in teams for line in team.lines]
    droplets = sum(1 for line in all_lines if line.kind == "Droplet")
    volumes = sum(1 for line in all_lines if line.kind == "Volume")
    balancers = sum(1 for line in all_lines if line.kind == "Load balancer")
    clusters = sum(team.cluster_count for team in teams)
    unbacked = sum(team.stateful_unbacked for team in teams)
    team_word = "team" if len(teams) == 1 else "teams"
    droplet_word = "stateful droplet" if unbacked == 1 else "stateful droplets"
    policy = "policy" if unbacked == 1 else "policies"
    lines = [
        f"📊 **DO Infrastructure Summary — {_summary_month(generated)}**",
        "",
        (
            f"• **Total Estimated Spend:** {fmt_money(_sum_monthly(all_lines))} / mo "
            f"across {len(teams)} {team_word}"
        ),
        (
            "• **Active Compute:** "
            + f"{_plural(droplets, 'Droplet')} | {_plural(clusters, 'DOKS Cluster')}"
        ),
        (
            "• **Storage & Networking:** "
            + f"{_plural(volumes, 'Volume')} | {_plural(balancers, 'Load Balancer')}"
        ),
        f"⚠️ **Action Needed:** {unbacked} {droplet_word} missing backup {policy}",
        "",
        "<details>",
        "<summary>🔍 Click to expand full team-by-team resource breakdown</summary>",
        "",
        "| Team | Droplets | Volumes | Monthly Spend |",
        "| :--- | :--- | :--- | :--- |",
    ]
    ordered = sorted(teams, key=lambda item: sort_label(item.label))
    for team in ordered:
        team_droplets = sum(1 for line in team.lines if line.kind == "Droplet")
        team_volumes = sum(1 for line in team.lines if line.kind == "Volume")
        lines.append(
            "| "
            + " | ".join(
                [
                    md_cell(heading_text(team.label)),
                    str(team_droplets),
                    str(team_volumes),
                    fmt_money(_sum_monthly(team.lines)),
                ]
            )
            + " |"
        )
    lines.extend(["", "</details>", ""])
    return "\n".join(lines)


def _priced(lines: list[Line]) -> list[Line]:
    return [line for line in lines if line.monthly is not None]


def _sum_monthly(lines: list[Line]) -> Decimal:
    return money(sum((line.monthly or Decimal("0") for line in _priced(lines)), Decimal("0")))


def _kind_totals(lines: list[Line]) -> list[tuple[str, Decimal, int]]:
    rows = []
    for kind in KIND_ORDER:
        selected = [line for line in lines if line.kind == kind]
        if selected:
            rows.append((kind, _sum_monthly(selected), len(selected)))
    return rows


def _tag_attributions(lines: list[Line]) -> dict[str, list[tuple[Line, Decimal]]]:
    grouped: dict[str, list[tuple[Line, Decimal]]] = {}
    for line in lines:
        tags = display_tags(line.tags)
        if line.monthly is None:
            shares = [None] * len(tags)
        else:
            shares = split_even(line.monthly, len(tags))
        for tag, share in zip(tags, shares):
            grouped.setdefault(tag, []).append((line, share))
    return grouped


def _render_lines_table(rows: list[tuple[Line, Decimal | None]]) -> list[str]:
    out = [
        "| Kind | Name | Region | Detail | All tags | Attributed | Full monthly |",
        "| --- | --- | --- | --- | --- | ---: | ---: |",
    ]
    ordered = sorted(rows, key=lambda item: (KIND_ORDER.index(item[0].kind), item[0].name.lower()))
    for line, share in ordered:
        tags = ", ".join(display_tags(line.tags))
        out.append(
            "| "
            + " | ".join(
                [
                    md_cell(line.kind),
                    md_cell(line.name),
                    md_cell(line.region),
                    md_cell(line.detail),
                    md_cell(tags),
                    fmt_money(share),
                    fmt_money(line.monthly),
                ]
            )
            + " |"
        )
    return out


def render_report(teams: list[TeamReport], generated: str) -> str:
    all_lines = [line for team in teams for line in team.lines]
    partial = any(team.errors for team in teams)
    unpriced = [line for line in all_lines if line.monthly is None]
    lines: list[str] = [
        "<!-- local only: do not commit — contains live resource names -->",
        "",
        "# DigitalOcean Monthly Cost Report",
        "",
        f"- Generated: {generated}",
        "- Access: read-only `GET https://api.digitalocean.com/v2/`",
        "- Estimate: current list-price run-rate for resources that exist now.",
        "",
    ]
    if partial:
        lines.append(
            "**PARTIAL — one or more API calls failed. Totals are incomplete.**"
        )
        lines.append("")
    lines.extend(
        [
            (
                "A DigitalOcean invoice also includes hourly proration, bandwidth overage, "
                + "Droplet backup plans, reserved IPs, managed databases, Spaces, container "
                + "registry storage, and taxes. Those are outside this report. Kubernetes "
                + "worker Droplets are billed under Kubernetes only, so they are not added again "
                + "under Droplets. Tag subtotals split a multi-tag resource evenly, so they add "
                + "up to the project total. Each resource row also shows the full monthly cost; "
                + "do not add full-cost rows across tags."
            ),
            "",
            "## Rates used",
            "",
            "| Resource | Monthly rate |",
            "| --- | --- |",
            "| Droplets | `size.price_monthly` from the API |",
            (
                "| Kubernetes nodes | worker size monthly price × current pool count. "
                + "Control plane is not billed. |"
            ),
            "| Volumes | $0.10 per GiB |",
            (
                "| Load balancers | Regional HTTP $12 per node; regional network "
                + "$15 per node; global $15 base. Legacy `lb-small` / "
                + "`lb-medium` / `lb-large` are 1 / 3 / 6 nodes. "
                + "Request and transfer overage is not estimated. |"
            ),
            (
                "| Snapshots | $0.06 per GiB, minimum $0.01 "
                + "(`GET /v2/snapshots`, Droplet and volume images) |"
            ),
            "",
            "## Total",
            "",
            f"**{fmt_money(_sum_monthly(all_lines))}** across {len(teams)} team(s).",
            "",
        ]
    )
    if unpriced:
        lines.append(
            f"{len(unpriced)} resource(s) have no price and are excluded from the total (`n/a`)."
        )
        lines.append("")
    lines.extend(
        [
            "| Kind | Monthly | Resources |",
            "| --- | ---: | ---: |",
        ]
    )
    if not all_lines:
        lines.append("| — | $0.00 | 0 |")
    for kind, total, count in _kind_totals(all_lines):
        lines.append(f"| {md_cell(kind)} | {fmt_money(total)} | {count} |")
    lines.append("")

    for team in teams:
        lines.append(f"## Team: {heading_text(team.label)}")
        lines.append("")
        lines.append(f"Team total: **{fmt_money(_sum_monthly(team.lines))}**")
        lines.append("")
        if team.empty_projects:
            lines.append(
                f"{team.empty_projects} project(s) contained no priced "
                "resource types and are omitted."
            )
            lines.append("")
        projects = sorted({line.project for line in team.lines}, key=sort_label)
        if not projects:
            lines.append("_No resources returned._")
            lines.append("")
        for project in projects:
            project_lines = [line for line in team.lines if line.project == project]
            lines.append(f"### Project: {heading_text(project)}")
            lines.append("")
            lines.append(
                f"Project total: **{fmt_money(_sum_monthly(project_lines))}**"
            )
            lines.append("")
            grouped = _tag_attributions(project_lines)
            lines.extend(
                [
                    "| Tag | Attributed monthly | Resources |",
                    "| --- | ---: | ---: |",
                ]
            )
            for tag in sorted(grouped, key=sort_label):
                shares = [share for _, share in grouped[tag] if share is not None]
                attributed = money(sum(shares, Decimal("0"))) if shares else None
                lines.append(
                    f"| {md_cell(tag)} | {fmt_money(attributed)} | {len(grouped[tag])} |"
                )
            lines.append("")
            for tag in sorted(grouped, key=sort_label):
                lines.append(f"#### Tag: {heading_text(tag)}")
                lines.append("")
                lines.extend(_render_lines_table(grouped[tag]))
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
    hostname = urllib.parse.urlparse(url).hostname
    if not hostname:
        return False
    host = hostname.lower()
    return (
        host == "discord.com"
        or host.endswith(".discord.com")
        or host == "discordapp.com"
        or host.endswith(".discordapp.com")
    )


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


def write_report(path: Path, markdown: str) -> None:
    """Create or replace the report as owner-read/write only."""
    flags = os.O_WRONLY | os.O_CREAT | os.O_TRUNC
    descriptor = os.open(path, flags, 0o600)
    try:
        os.chmod(path, 0o600)
        with os.fdopen(descriptor, "w", encoding="utf-8", newline="\n") as handle:
            handle.write(markdown)
            descriptor = -1
    finally:
        if descriptor >= 0:
            os.close(descriptor)


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
        teams.append(TeamAuth(team_label, token, env_name))
    return teams


def _configure_stdio() -> None:
    for stream in (sys.stdout, sys.stderr):
        reconfigure = getattr(stream, "reconfigure", None)
        if reconfigure is None:
            continue
        try:
            reconfigure(encoding="utf-8", errors="replace")
        except (OSError, ValueError):
            # Best effort: a stream that cannot be reconfigured (detached, or already
            # written to) keeps its encoding; the report still prints.
            pass


def main(argv: list[str] | None = None) -> int:
    args = list(sys.argv[1:] if argv is None else argv)
    if args == ["--self-check"]:
        self_check()
        print("self-check ok")
        return 0
    if args:
        print("usage: python3 do_cost_reporter.py [--self-check]", file=sys.stderr)
        return 2

    _configure_stdio()
    if requests is None:
        print("install dependencies: pip install -r requirements.txt", file=sys.stderr)
        return 1
    teams = load_teams()
    reports: list[TeamReport] = []
    for auth in teams:
        client = DigitalOceanClient(auth)
        try:
            try:
                reports.append(collect_team(client))
            except DOAuthError as exc:
                reports.append(TeamReport(label=auth.label, errors=[str(exc)]))
        finally:
            client.close()

    generated = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")
    markdown = render_report(reports, generated)
    sys.stdout.write(markdown)
    if not markdown.endswith("\n"):
        sys.stdout.write("\n")
    destination = Path.cwd() / REPORT_FILENAME
    write_report(destination, markdown)
    print(f"wrote {destination}", file=sys.stderr)

    webhook_set = bool(os.environ.get("WEBHOOK_URL", "").strip())
    webhook_ok = True
    if webhook_set:
        webhook_ok = send_webhook_report(markdown)
    nostr_failed = _publish_nostr(buzz_summary(reports, generated)) == "failed"
    incomplete = any(team.errors for team in reports)
    if incomplete or (webhook_set and not webhook_ok) or nostr_failed:
        return 1
    return 0


def _publish_nostr(markdown: str, private_key: str | None = None) -> str:
    scripts_dir = str(Path(__file__).resolve().parent.parent)
    if scripts_dir not in sys.path:
        sys.path.insert(0, scripts_dir)
    from publish_to_buzz import publish_to_buzz

    return publish_to_buzz(markdown, private_key=private_key)


def self_check() -> None:
    """Offline checks for pricing, grouping, and the token URL guard."""
    assert _is_discord("https://discord.com/api/webhooks/1/example")
    assert _is_discord("https://hooks.discordapp.com/api/webhooks/1/example")
    assert not _is_discord("https://notdiscord.com/hook")
    assert not _is_discord("https://discord.com.evil.example/hook")
    assert not _is_discord("https://evil.example/path?host=discord.com")
    assert_digitalocean_url("https://api.digitalocean.com/v2/droplets")
    try:
        assert_digitalocean_url("https://evil.example/v2/droplets")
    except DOAPIError:
        pass
    else:
        raise AssertionError("token URL guard accepted a foreign host")
    try:
        assert_digitalocean_url("http://api.digitalocean.com/v2/droplets")
    except DOAPIError:
        pass
    else:
        raise AssertionError("token URL guard accepted plain HTTP")

    assert not hasattr(DigitalOceanClient, "post")
    assert load_balancer_monthly({"type": "REGIONAL", "size_unit": 2})[0] == Decimal("24.00")
    assert load_balancer_monthly(
        {"type": "REGIONAL_NETWORK", "size_unit": 1}
    )[0] == Decimal("15.00")
    assert load_balancer_monthly({"type": "GLOBAL", "size_unit": 3})[0] == Decimal("15.00")
    assert load_balancer_monthly({"size": "lb-large"})[0] == Decimal("72.00")
    assert load_balancer_monthly({"size": "lb-small"})[0] == Decimal("12.00")
    network = {"forwarding_rules": [{"entry_protocol": "tcp"}, {"entry_protocol": "udp"}]}
    assert infer_lb_type(network) == "REGIONAL_NETWORK"
    assert load_balancer_monthly(network)[0] == Decimal("15.00")

    assert volume_monthly({"size_gigabytes": 100}) == Decimal("10.00")
    assert volume_monthly({"size_gigabytes": 1}) == Decimal("0.10")
    assert snapshot_monthly({"size_gigabytes": Decimal("0.1")}) == Decimal("0.01")
    assert snapshot_monthly({"size_gigabytes": 10}) == Decimal("0.60")
    assert snapshot_monthly({"size_gigabytes": 0}) == Decimal("0.00")
    assert split_even(Decimal("10.00"), 3) == [Decimal("3.34"), Decimal("3.33"), Decimal("3.33")]
    assert sum(split_even(Decimal("0.01"), 3), Decimal("0")) == Decimal("0.01")

    report = build_team_report(
        "example-team",
        sizes=[
            {"slug": "s-2vcpu-4gb", "price_monthly": 24},
            {"slug": "s-1vcpu-1gb", "price_monthly": 6},
        ],
        projects=[{"id": "proj-1", "name": "Example"}],
        urns_by_project_id={
            "proj-1": ["do:droplet:11", "do:kubernetes:cluster-1", "do:loadbalancer:lb-1"],
        },
        droplets=[
            {
                "id": 10,
                "name": "worker",
                "status": "active",
                "tags": ["k8s"],
                "region": {"slug": "nyc3"},
                "size": {"slug": "s-2vcpu-4gb", "price_monthly": 24},
            },
            {
                "id": 11,
                "name": "web|edge",
                "status": "off",
                "tags": ["production", "weown-ai"],
                "region": {"slug": "nyc3"},
                "size": {"slug": "s-1vcpu-1gb", "price_monthly": 6},
            },
        ],
        clusters=[
            {
                "id": "cluster-1",
                "name": "example-cluster",
                "region": "nyc3",
                "tags": ["production"],
                "node_pools": [
                    {
                        "name": "pool",
                        "size": "s-2vcpu-4gb",
                        "count": 1,
                        "auto_scale": True,
                        "min_nodes": 1,
                        "max_nodes": 3,
                        "nodes": [{"droplet_id": "10"}],
                    }
                ],
            }
        ],
        volumes=[{
            "id": "vol-1",
            "name": "data",
            "region": {"slug": "nyc3"},
            "size_gigabytes": 50,
            "tags": [],
            "droplet_ids": [11],
        }],
        load_balancers=[
            {
                "id": "lb-1",
                "name": "edge",
                "region": {"slug": "nyc3"},
                "type": "REGIONAL",
                "size_unit": 1,
                "tags": ["production"],
            }
        ],
        snapshots=[
            {
                "id": "snap-1",
                "name": "disk",
                "regions": ["nyc3"],
                "resource_type": "droplet",
                "size_gigabytes": Decimal("1.5"),
                "tags": [],
            }
        ],
    )
    kinds = {line.kind: line for line in report.lines}
    assert "worker" not in {line.name for line in report.lines}
    assert kinds["Kubernetes"].monthly == Decimal("24.00")
    assert kinds["Kubernetes"].project == "Example"
    droplet = next(line for line in report.lines if line.kind == "Droplet")
    assert droplet.monthly == Decimal("6.00")
    assert droplet.tags == ("production", "weown-ai")
    volume = next(line for line in report.lines if line.kind == "Volume")
    assert volume.project == UNALLOCATED
    assert volume.monthly == Decimal("5.00")
    assert volume.tags == ()
    assert next(
        line for line in report.lines if line.kind == "Load balancer"
    ).monthly == Decimal("12.00")
    assert next(
        line for line in report.lines if line.kind == "Snapshot"
    ).monthly == Decimal("0.09")
    # 24 + 6 + 5 + 12 + 0.09
    assert _sum_monthly(report.lines) == Decimal("47.09")
    assert report.cluster_count == 1
    assert report.stateful_unbacked == 1
    rendered = render_report([report], "2026-10-01 00:00:00 UTC")
    summary = buzz_summary([report], "2026-10-01 00:00:00 UTC")
    assert summary.startswith("📊 **DO Infrastructure Summary — October 2026**")
    assert "**Total Estimated Spend:** $47.09 / mo across 1 team" in summary
    assert "**Active Compute:** 1 Droplet | 1 DOKS Cluster" in summary
    assert "**Storage & Networking:** 1 Volume | 1 Load Balancer" in summary
    assert "**Action Needed:** 1 stateful droplet missing backup policy" in summary
    assert "| example-team | 1 | 1 | $47.09 |" in summary
    assert "web|edge" not in summary
    assert "<details>" in summary and "</details>" in summary
    assert "web\\|edge" in rendered
    assert UNALLOCATED in rendered
    assert "| Droplet | worker |" not in rendered
    grouped_all = _tag_attributions(report.lines)
    attributed = sum(
        (share for rows in grouped_all.values() for _, share in rows if share is not None),
        Decimal("0"),
    )
    assert money(attributed) == _sum_monthly(report.lines)
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
    shares = _tag_attributions([droplet])
    assert sum(share for _, share in shares["production"]) == Decimal("3.00")
    assert sum(share for _, share in shares["weown-ai"]) == Decimal("3.00")
    chunks = _chunks("a\nb\nc\n", 3)
    assert "".join(chunks) == "a\nb\nc\n"
    assert all(len(chunk) <= 3 for chunk in chunks)
    assert _redact_progress("projects/d0eb061e-0348-49a9-b9dd-55aa32bc79d6/resources") == (
        "projects/<id>/resources"
    )
    assert _publish_nostr("local report", private_key="") == "skipped"
    # A 401 names the variable that holds the rejected token, extra teams included.
    os.environ.update({"DIGITALOCEAN_TOKEN": "x", "DO_EXTRA_TEAM_TOKENS": "Ops:DO_OPS_TOKEN",
                       "DO_OPS_TOKEN": "y"})
    teams = load_teams()
    assert [(t.label, t.token_env) for t in teams][1:] == [("Ops", "DO_OPS_TOKEN")]
    assert teams[0].token_env == "DIGITALOCEAN_TOKEN"
    for auth, env_name in ((teams[0], "DIGITALOCEAN_TOKEN"), (teams[1], "DO_OPS_TOKEN")):
        client = DigitalOceanClient(auth)
        client._session.get = lambda *a, **k: type("R", (), {"status_code": 401, "headers": {}})()
        try:
            client.get_json(API_ROOT + "account")
        except DOAuthError as exc:
            assert f"Set {env_name} to" in str(exc), str(exc)
        else:
            raise AssertionError("a 401 was not raised as DOAuthError")
        finally:
            client.close()


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except BrokenPipeError:
        raise SystemExit(0)
