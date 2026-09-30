#!/usr/bin/env python3
"""Publish a Markdown report to the Buzz Nostr relay.

Credentials and routing come from the environment:

- NOSTR_PRIVATE_KEY: nsec bech32 or 64-character hex. When this is unset the
  call returns "skipped" and does not raise.
- NOSTR_RELAY_URL: websocket URL. Default wss://felg.weown.buzz/
- BUZZ_CHANNEL_ID: when set, the note is a NIP-28 channel message (kind 42)
  with an ``e`` root tag and an ``h`` tag so Buzz can file it in that channel.
- BUZZ_CHANNEL_NAME: added as a ``t`` tag. If no channel id is set, the note
  stays a kind 1 text note carrying only that tag.

With neither channel variable set, the note is a standard kind 1 root note.
The private key is used only to sign. It is never printed.
"""

from __future__ import annotations

import asyncio
import contextlib
import io
import os
import re
import sys
import urllib.parse
from datetime import timedelta

DEFAULT_RELAY_URL = "wss://felg.weown.buzz/"
# Common relay event caps are 64 KiB of JSON. Stay under that with room for
# the event envelope, then split a long report into numbered notes.
MAX_NOTE_CHARS = 60000
_NSEC = re.compile(r"nsec1[0-9a-z]+")
_HEX_KEY = re.compile(r"\b[0-9a-fA-F]{64}\b")


class PublishError(Exception):
    """A safe, key-free description of why publishing did not succeed."""


class NoteRoute:
    """Kind and tags for one report note. Tags are NIP tag arrays."""

    def __init__(self, kind: int, tags: list[list[str]]) -> None:
        self.kind = kind
        self.tags = tags


def _redact(text: str) -> str:
    text = _NSEC.sub("nsec1<redacted>", text)
    return _HEX_KEY.sub("<redacted>", text)


def split_note(content: str, limit: int = MAX_NOTE_CHARS) -> list[str]:
    """Split a report into Kind 1 bodies that each fit in `limit` characters."""
    if len(content) <= limit:
        return [content]
    header_room = 24
    body_limit = max(limit - header_room, 1)
    bodies = _pack(content, body_limit)
    total = len(bodies)
    notes: list[str] = []
    for index, body in enumerate(bodies, start=1):
        note = f"[part {index}/{total}]\n{body}"
        if len(note) > limit:
            raise PublishError("a report line is longer than one Nostr note")
        notes.append(note)
    return notes


def _pack(content: str, limit: int) -> list[str]:
    parts: list[str] = []
    current: list[str] = []
    size = 0
    for block in content.splitlines(keepends=True):
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


def _relay_url(explicit: str | None) -> str:
    raw = (explicit if explicit is not None else os.environ.get("NOSTR_RELAY_URL", "")).strip()
    url = raw or DEFAULT_RELAY_URL
    parsed = urllib.parse.urlparse(url)
    if parsed.scheme not in {"ws", "wss"} or not parsed.netloc:
        raise PublishError("NOSTR_RELAY_URL must be a ws:// or wss:// URL")
    return url


def _env_or_explicit(explicit: str | None, env_name: str) -> str:
    if explicit is None:
        return os.environ.get(env_name, "").strip()
    return explicit.strip()


def _reject_secret_shaped(value: str, env_name: str) -> None:
    if value.lower().startswith("nsec1") or "dop_v1" in value.lower():
        raise PublishError(f"{env_name} must be a channel id or name, not a private key")


def note_route(
    relay: str,
    channel_id: str | None = None,
    channel_name: str | None = None,
) -> NoteRoute:
    """Choose kind 42 when a channel id is set, otherwise a kind 1 note.

    ``None`` reads the environment. ``""`` means that variable is unset.
    """
    channel_id = _env_or_explicit(channel_id, "BUZZ_CHANNEL_ID")
    channel_name = _env_or_explicit(channel_name, "BUZZ_CHANNEL_NAME")
    _reject_secret_shaped(channel_id, "BUZZ_CHANNEL_ID")
    _reject_secret_shaped(channel_name, "BUZZ_CHANNEL_NAME")
    if channel_id:
        tags = [
            ["e", channel_id, relay, "root"],
            ["h", channel_id],
        ]
        if channel_name:
            tags.append(["t", channel_name])
        return NoteRoute(42, tags)
    if channel_name:
        return NoteRoute(1, [["t", channel_name]])
    return NoteRoute(1, [])


def _load_keys(secret: str):
    try:
        from nostr_sdk import Keys
    except ImportError as exc:
        raise PublishError("install nostr-sdk (pip install -r requirements.txt)") from exc
    try:
        return Keys.parse(secret.strip())
    except Exception as exc:
        raise PublishError(
            "NOSTR_PRIVATE_KEY could not be parsed (expected nsec bech32 or 64-character hex)"
        ) from exc


def _kind_for(route: NoteRoute):
    from nostr_sdk import Kind, KindStandard

    if route.kind == 42:
        return Kind.from_std(KindStandard.CHANNEL_MESSAGE)
    if route.kind == 1:
        return Kind.from_std(KindStandard.TEXT_NOTE)
    raise PublishError("unsupported Nostr kind")


def _build_event(content: str, secret: str, route: NoteRoute):
    from nostr_sdk import EventBuilder, Tag

    keys = _load_keys(secret)
    builder = EventBuilder(_kind_for(route), content)
    if route.tags:
        builder = builder.tags([Tag.parse(tag) for tag in route.tags])
    return builder.finalize_unsigned(keys.public_key()).sign(keys)


async def _send(notes: list[str], secret: str, relay: str, route: NoteRoute) -> list[str]:
    from nostr_sdk import Client, RelayUrl

    events = [_build_event(note, secret, route) for note in notes]
    client = Client()
    try:
        await client.add_relay(RelayUrl.parse(relay))
        await client.connect(timedelta(seconds=20))
        published: list[str] = []
        for event in events:
            output = await client.send_event(event, ok_timeout=timedelta(seconds=30))
            if not output.success:
                reasons = "; ".join(_redact(str(reason)) for reason in output.failed.values())
                raise PublishError(reasons or "relay did not accept the note")
            published.append(event.id().to_hex())
        return published
    finally:
        await client.disconnect()


def publish_to_buzz(
    content: str,
    private_key: str | None = None,
    relay_url: str | None = None,
    channel_id: str | None = None,
    channel_name: str | None = None,
) -> str:
    """Publish `content` as one or more notes.

    Returns "skipped" when no private key is configured, "ok" when every note
    is accepted, and "failed" when signing or the relay fails. Does not raise.
    """
    if private_key is None:
        private_key = os.environ.get("NOSTR_PRIVATE_KEY", "")
    secret = private_key.strip()
    if not secret:
        print("Nostr publish skipped: NOSTR_PRIVATE_KEY is not set", file=sys.stderr)
        return "skipped"
    try:
        relay = _relay_url(relay_url)
        route = note_route(relay, channel_id, channel_name)
        notes = split_note(content)
        ids = asyncio.run(_send(notes, secret, relay, route))
    except PublishError as exc:
        print(f"Nostr publish failed: {_redact(str(exc))}", file=sys.stderr)
        return "failed"
    except Exception as exc:
        print(f"Nostr publish failed: {type(exc).__name__}", file=sys.stderr)
        return "failed"
    label = "channel message" if route.kind == 42 else "note"
    if len(ids) == 1:
        print(f"Nostr {label} published ({ids[0]})", file=sys.stderr)
    else:
        print(f"Nostr {label}s published ({len(ids)} parts)", file=sys.stderr)
    return "ok"


def self_check() -> None:
    assert publish_to_buzz("hello", private_key="") == "skipped"
    captured = io.StringIO()
    with contextlib.redirect_stderr(captured):
        failed = publish_to_buzz(
            "hello",
            private_key="not-a-key",
            channel_id="",
            channel_name="",
        )
    assert failed == "failed"
    assert "not-a-key" not in captured.getvalue()
    relay = DEFAULT_RELAY_URL
    root = note_route(relay, channel_id="", channel_name="")
    assert root.kind == 1 and root.tags == []
    named = note_route(relay, channel_id="", channel_name="ops")
    assert named.kind == 1 and named.tags == [["t", "ops"]]
    channel = note_route(relay, channel_id="channel-1", channel_name="ops")
    assert channel.kind == 42
    assert channel.tags[0] == ["e", "channel-1", relay, "root"]
    assert channel.tags[1] == ["h", "channel-1"]
    assert channel.tags[2] == ["t", "ops"]
    try:
        note_route(relay, channel_id="nsec1example", channel_name="")
    except PublishError:
        pass
    else:
        raise AssertionError("a private key was accepted as a channel id")
    notes = split_note("line\n" * 40, limit=80)
    assert len(notes) > 1
    assert all(len(note) <= 80 for note in notes)
    assert "".join(note.split("\n", 1)[1] for note in notes) == "line\n" * 40
    from nostr_sdk import Keys

    keys = Keys.generate()
    public = keys.public_key().to_hex()
    assert Keys.parse(keys.secret_key().to_hex()).public_key().to_hex() == public
    assert Keys.parse(keys.secret_key().to_bech32()).public_key().to_hex() == public
    event = _build_event(
        "offline",
        keys.secret_key().to_hex(),
        note_route(relay, channel_id="channel-1", channel_name=""),
    )
    assert event.kind().as_u16() == 42
    assert event.content() == "offline"
    tag_rows = [list(tag.to_vec()) for tag in event.tags()]
    assert ["e", "channel-1", relay, "root"] in tag_rows
    assert ["h", "channel-1"] in tag_rows
    try:
        _relay_url("https://example.com")
    except PublishError:
        pass
    else:
        raise AssertionError("non-websocket relay URL was accepted")


if __name__ == "__main__":
    if sys.argv[1:] == ["--self-check"]:
        self_check()
        print("self-check ok")
        raise SystemExit(0)
    # Read the report from stdin so a key on the command line is never required.
    # A missing key is a skip, not a crash.
    status = publish_to_buzz(sys.stdin.read())
    raise SystemExit(0 if status in {"ok", "skipped"} else 1)
