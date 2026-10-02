#!/usr/bin/env python3
"""Publish a Markdown report to the Buzz Nostr relay.

Credentials and routing come from the environment:

- NOSTR_PRIVATE_KEY: nsec bech32 or 64-character hex. When this is unset the
  call returns "skipped" and does not raise.
- NOSTR_RELAY_URL: required ``wss://`` URL. There is no default.
- BUZZ_CHANNEL_ID: when set, the same markdown is signed twice. Kind 1
  carries ``e`` (root), ``h``, ``t``, and ``p`` (the sender pubkey). Kind 9
  is the group-chat note Buzz channel views index, with ``h``, ``t``, and
  ``p``. The relay rejects Kind 42 (``restricted: unknown event kind``).
  A Kind 9 refusal of ``unknown event kind`` is logged and does not drop
  the Kind 1 note. A 64-character hex event id or a short public channel
  id is accepted.
- The ``t`` tag is ``Cloud&Infrastructure``.
- NOTIFICATION_PUBKEYS: optional comma-separated 64-hex public keys. Each
  one is a ``p`` tag so Buzz can notify that person. A private key is refused.
  Pass ``notify=False`` to publish without those tags.

With no channel id, the note is a Kind 1 root note. Line breaks in the
markdown are kept.
The private key is used only to sign and, when the relay asks, to answer
NIP-42 AUTH. It is never printed.
"""

from __future__ import annotations

import asyncio
import contextlib
import io
import json
import os
import re
import sys
import urllib.parse
from datetime import timedelta

# Common relay event caps are 64 KiB of JSON. Stay under that with room for
# the event envelope, then split a long report into numbered notes.
MAX_NOTE_BYTES = 48000
_NSEC = re.compile(r"nsec1[0-9a-z]+")
_HEX_KEY = re.compile(r"\b[0-9a-fA-F]{64}\b")
_EVENT_ID = re.compile(r"^[0-9a-fA-F]{64}$")
_CHANNEL_REF = re.compile(r"[A-Za-z0-9_.:-]{1,200}")
BUZZ_TOPIC = "Cloud&Infrastructure"


class PublishError(Exception):
    """A safe, key-free description of why publishing did not succeed."""


class RelayRejected(PublishError):
    """The relay answered send_event or NIP-42 AUTH and refused the note."""


class NoteRoute:
    """Kind and tags for one report note. Tags are NIP tag arrays."""

    def __init__(self, kind: int, tags: list[list[str]]) -> None:
        self.kind = kind
        self.tags = tags


def _redact(text: str) -> str:
    text = _NSEC.sub("nsec1<redacted>", text)
    return _HEX_KEY.sub("<redacted>", text)


def _encoded_len(text: str) -> int:
    """UTF-8 size of the JSON string, including quotes and escapes."""
    return len(json.dumps(text, ensure_ascii=False).encode("utf-8"))


def format_report(content: str) -> str:
    """Keep markdown line breaks. Blank lines stay blank."""
    return content.replace("\r\n", "\n").replace("\r", "\n")


def split_note(content: str, limit: int = MAX_NOTE_BYTES) -> list[str]:
    """Split a report so each note's JSON text stays within `limit` bytes."""
    if _encoded_len(content) <= limit:
        return [content]
    header = _encoded_len("[part 999/999]\n")
    body_limit = limit - header
    if body_limit < 8:
        raise PublishError("note byte limit is too small")
    bodies = _pack(content, body_limit)
    total = len(bodies)
    notes: list[str] = []
    for index, body in enumerate(bodies, start=1):
        note = f"[part {index}/{total}]\n{body}"
        if _encoded_len(note) > limit:
            raise PublishError("a report line is longer than one Nostr note")
        notes.append(note)
    return notes


def _pack(content: str, limit: int) -> list[str]:
    parts: list[str] = []
    current = ""
    for block in content.splitlines(keepends=True):
        if _encoded_len(block) > limit:
            if current:
                parts.append(current)
                current = ""
            parts.extend(_slice_to_limit(block, limit))
            continue
        candidate = current + block
        if current and _encoded_len(candidate) > limit:
            parts.append(current)
            current = block
        else:
            current = candidate
    if current:
        parts.append(current)
    return parts


def _slice_to_limit(block: str, limit: int) -> list[str]:
    pieces: list[str] = []
    start = 0
    while start < len(block):
        lo = start + 1
        hi = len(block)
        best = start
        while lo <= hi:
            mid = (lo + hi) // 2
            if _encoded_len(block[start:mid]) <= limit:
                best = mid
                lo = mid + 1
            else:
                hi = mid - 1
        if best == start:
            raise PublishError("a report character exceeds one Nostr note")
        pieces.append(block[start:best])
        start = best
    return pieces


def _relay_url(explicit: str | None) -> str:
    raw = (explicit if explicit is not None else os.environ.get("NOSTR_RELAY_URL", "")).strip()
    if not raw:
        raise PublishError("Set NOSTR_RELAY_URL to a wss:// URL (no default)")
    parsed = urllib.parse.urlparse(raw)
    if parsed.scheme != "wss" or not parsed.hostname:
        raise PublishError("NOSTR_RELAY_URL must be a wss:// URL")
    return raw


def _channel_ref(value: str, env_name: str) -> str:
    """Accept a NIP-28 event id or a short public channel id. Never a key."""
    raw = value.strip()
    if raw.lower().startswith("nostr:"):
        raw = raw[6:]
    _reject_secret_shaped(raw, env_name)
    if _EVENT_ID.fullmatch(raw):
        return raw.lower()
    if _CHANNEL_REF.fullmatch(raw):
        return raw
    raise PublishError(
        f"{env_name} must be a 64-hex event id or a short public channel id"
    )


def _env_or_explicit(explicit: str | None, env_name: str) -> str:
    if explicit is None:
        return os.environ.get(env_name, "").strip()
    return explicit.strip()


def _reject_secret_shaped(value: str, env_name: str) -> None:
    lowered = value.lower()
    if "nsec1" in lowered or "dop_v1" in lowered:
        raise PublishError(f"{env_name} must be a channel id or name, not a private key")


def note_route(
    relay: str,
    channel_id: str | None = None,
    channel_name: str | None = None,
) -> NoteRoute:
    """Always a Kind 1 text note. Channel tags route it inside Buzz.

    ``None`` reads the environment. ``""`` means that variable is unset.
    The ``e`` tag's relay is the ``wss://`` URL this note is sent to.
    """
    channel_id = _env_or_explicit(channel_id, "BUZZ_CHANNEL_ID")
    channel_name = _env_or_explicit(channel_name, "BUZZ_CHANNEL_NAME")
    _reject_secret_shaped(channel_id, "BUZZ_CHANNEL_ID")
    _reject_secret_shaped(channel_name, "BUZZ_CHANNEL_NAME")
    if channel_id:
        channel_id = _channel_ref(channel_id, "BUZZ_CHANNEL_ID")
        return NoteRoute(
            1,
            [
                ["e", channel_id, relay, "root"],
                ["h", channel_id],
                ["t", BUZZ_TOPIC],
            ],
        )
    if channel_name:
        return NoteRoute(1, [["t", channel_name]])
    return NoteRoute(1, [])


def report_routes(
    relay: str,
    channel_id: str | None = None,
    channel_name: str | None = None,
) -> list[NoteRoute]:
    """Kind 1, plus Kind 9 when a channel id is set.

    Kind 9 is a root group-chat note (``h``, no ``e``). An ``e`` tag on Kind 9
    would mark it as a reply and the channel view can hide it.
    """
    primary = note_route(relay, channel_id, channel_name)
    if not _channel_id_of(primary):
        return [primary]
    group_tags = [tag for tag in primary.tags if tag and tag[0] != "e"]
    return [primary, NoteRoute(9, group_tags)]


def _normalize_key(secret: str) -> str:
    """Strip spaces, newlines, and one pair of wrapping quotes. Never prints the value."""
    text = secret.strip().strip('"').strip("'").strip()
    return "".join(text.split())


def _load_keys(secret: str):
    try:
        from nostr_sdk import Keys
    except ImportError as exc:
        raise PublishError("install nostr-sdk (pip install -r requirements.txt)") from exc
    text = _normalize_key(secret)
    try:
        keys = Keys.parse(text)
        # nsec is decoded to the same key as its 64-character hex form.
        if text.lower().startswith("nsec"):
            keys = Keys.parse(keys.secret_key().to_hex())
        return keys
    except Exception as exc:
        raise PublishError(
            "NOSTR_PRIVATE_KEY could not be parsed (expected nsec bech32 or 64-character hex)"
        ) from exc


def _kind_for(route: NoteRoute):
    from nostr_sdk import Kind, KindStandard

    if route.kind == 1:
        return Kind.from_std(KindStandard.TEXT_NOTE)
    if route.kind == 9:
        return Kind.from_std(KindStandard.CHAT_MESSAGE)
    raise PublishError("unsupported Nostr kind")


def _build_event(
    content: str,
    secret: str,
    route: NoteRoute,
    mentions: list[str] | None = None,
):
    keys = _load_keys(secret)
    return _sign_event(content, keys, route, mentions)


def notification_pubkeys(explicit: str | None = None) -> list[str]:
    """Public hex keys to mention. Never prints a rejected value."""
    raw = os.environ.get("NOTIFICATION_PUBKEYS", "") if explicit is None else explicit
    found: list[str] = []
    for part in raw.split(","):
        text = "".join(part.strip().split()).lower()
        if text.startswith("nostr:"):
            text = text[6:]
        if not text:
            continue
        if "nsec1" in text or "dop_v1" in text:
            raise PublishError(
                "NOTIFICATION_PUBKEYS must be public hex keys, not a private key"
            )
        if not _EVENT_ID.fullmatch(text):
            raise PublishError(
                "NOTIFICATION_PUBKEYS entries must be 64-character hex public keys"
            )
        if text not in found:
            found.append(text)
    return found


def _has_p(tags: list[list[str]], pubkey: str) -> bool:
    return any(len(tag) >= 2 and tag[0] == "p" and tag[1] == pubkey for tag in tags)


def _event_tags(route: NoteRoute, keys, mentions: list[str] | None = None) -> list[list[str]]:
    """Copy route tags, add the sender ``p`` tag, then each mention."""
    tags = [list(tag) for tag in route.tags]
    if _channel_id_of(route):
        pubkey = keys.public_key().to_hex()
        if not _has_p(tags, pubkey):
            tags.append(["p", pubkey])
    for pubkey in mentions or []:
        if not _has_p(tags, pubkey):
            tags.append(["p", pubkey])
    return tags


def _reject_signing_key_in_tags(tags: list[list[str]], keys) -> None:
    """Tags are public. Refuse a tag that carries the signing key in hex or nsec form."""
    secret = keys.secret_key()
    forms = (secret.to_hex().lower(), secret.to_bech32().lower())
    for tag in tags:
        for value in tag[1:]:
            lowered = value.lower()
            if any(form in lowered for form in forms):
                raise PublishError(
                    "a channel id or name is the signing key; refusing to publish it"
                )


def _sign_event(content: str, keys, route: NoteRoute, mentions: list[str] | None = None):
    from nostr_sdk import EventBuilder, Tag

    builder = EventBuilder(_kind_for(route), content)
    tags = _event_tags(route, keys, mentions)
    _reject_signing_key_in_tags(tags, keys)
    if tags:
        builder = builder.tags([Tag.parse(tag) for tag in tags])
    return builder.finalize_unsigned(keys.public_key()).sign(keys)


def _unknown_kind(detail: str) -> bool:
    return "unknown event kind" in detail.lower()


async def _send(
    notes: list[str],
    secret: str,
    relay: str,
    routes: list[NoteRoute],
    mentions: list[str] | None = None,
) -> list[str]:
    from nostr_sdk import (
        ClientBuilder,
        RelayUrl,
        SignerAuthenticator,
        uniffi_set_event_loop,
    )

    keys = _load_keys(secret)
    batches = [
        (route, [_sign_event(note, keys, route, mentions) for note in notes])
        for route in routes
    ]
    # NIP-42 AUTH runs on a Rust thread. nostr-sdk 0.45 only finds an asyncio
    # loop there after uniffi_set_event_loop (rust-nostr.org "No running event loop").
    # Without it, make_auth_event raises and the relay drops the connection.
    uniffi_set_event_loop(asyncio.get_running_loop())
    try:
        client = ClientBuilder().authenticator(SignerAuthenticator(keys)).build()
        try:
            await client.add_relay(RelayUrl.parse(relay))
            await client.connect(timedelta(seconds=20))
            published: list[str] = []
            kind1_sent = False
            channel = _channel_id_of(routes[0]) if routes else ""
            for route, events in batches:
                _emit(
                    f"[INFO] Publishing Kind {route.kind} report note to channel ID: "
                    + (channel or "-")
                )
                try:
                    for event in events:
                        output = await client.send_event(
                            event, ok_timeout=timedelta(seconds=30)
                        )
                        if not output.success:
                            reasons = "; ".join(
                                _redact(str(reason)) for reason in output.failed.values()
                            )
                            raise RelayRejected(reasons or "relay did not accept the note")
                        published.append(event.id().to_hex())
                except RelayRejected as exc:
                    if route.kind == 9 and kind1_sent and _unknown_kind(str(exc)):
                        _emit(
                            "[INFO] Kind 9 was not accepted by the relay: "
                            + _redact(str(exc))
                        )
                        continue
                    raise
                if route.kind == 1:
                    kind1_sent = True
            return published
        finally:
            await client.disconnect()
    finally:
        uniffi_set_event_loop(None)


async def _check_auth_through_local_relay(keys) -> None:
    """Publish through a local relay that demands NIP-42 AUTH before it accepts a note.

    The Rust client answers the challenge by calling back into Python's
    SignerAuthenticator. Without uniffi_set_event_loop in _send that callback has
    no event loop and the note times out, so this check fails.
    """
    from nostr_sdk import LocalRelayBuilder, LocalRelayBuilderNip42, LocalRelayBuilderNip42Mode

    relay = (
        LocalRelayBuilder()
        .addr("127.0.0.1")
        .nip42(LocalRelayBuilderNip42(mode=LocalRelayBuilderNip42Mode.WRITE))
        .build()
    )
    await relay.run()
    try:
        url = str(await relay.url())
        route = NoteRoute(1, [])
        with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            ids = await asyncio.wait_for(
                _send(["auth check"], keys.secret_key().to_hex(), url, [route]), 60
            )
        if len(ids) != 1:
            raise AssertionError("the NIP-42 relay did not accept the note")
    finally:
        relay.shutdown()


def _success_line(event_id: str, channel_id: str, relay: str) -> str:
    channel = channel_id or "-"
    return f"[SUCCESS] Published event {event_id} to channel {channel} on {relay}"


def _channel_id_of(route: NoteRoute) -> str:
    for tag in route.tags:
        if tag and tag[0] == "h" and len(tag) > 1:
            return tag[1]
    return ""


def _emit(line: str) -> None:
    """stdout for the caller, stderr because the workflow discards report stdout."""
    print(line)
    print(line, file=sys.stderr)


def _relay_error(detail: str) -> None:
    """Print the relay's own message and raise. The key is already redacted."""
    safe = _redact(detail)
    _emit(safe)
    raise RelayRejected(safe)


def publish_to_buzz(
    content: str,
    private_key: str | None = None,
    relay_url: str | None = None,
    channel_id: str | None = None,
    channel_name: str | None = None,
    notify: bool = True,
) -> str:
    """Publish `content` as one or more notes.

    Returns "skipped" when no private key is configured, "ok" when the Kind 1
    note is accepted, and "failed" for a key or URL error. A relay refusal,
    including NIP-42 authentication failed, is printed and raised as
    RelayRejected. A Kind 9 ``unknown event kind`` answer is logged and the
    Kind 1 note still counts as published.
    """
    if private_key is None:
        private_key = os.environ.get("NOSTR_PRIVATE_KEY", "")
    secret = _normalize_key(private_key)
    if not secret:
        print("Nostr publish skipped: NOSTR_PRIVATE_KEY is not set", file=sys.stderr)
        return "skipped"
    try:
        relay = _relay_url(relay_url)
        routes = report_routes(relay, channel_id, channel_name)
        notes = split_note(format_report(content))
        mentions = notification_pubkeys() if notify else []
        ids = asyncio.run(_send(notes, secret, relay, routes, mentions))
    except RelayRejected as exc:
        _relay_error(str(exc))
    except PublishError as exc:
        detail = _redact(str(exc))
        print(f"Nostr publish failed: {detail}", file=sys.stderr)
        return "failed"
    except Exception as exc:
        detail = _redact(str(exc))
        _relay_error(detail or type(exc).__name__)
    channel = _channel_id_of(routes[0]) if routes else ""
    for event_id in ids:
        _emit(_success_line(event_id, channel, relay))
    return "ok"


def self_check() -> None:
    assert publish_to_buzz("hello", private_key="") == "skipped"
    captured = io.StringIO()
    with contextlib.redirect_stderr(captured):
        failed = publish_to_buzz(
            "hello",
            private_key="not-a-key",
            relay_url="wss://relay.example.com/",
            channel_id="",
            channel_name="",
            notify=False,
        )
    assert failed == "failed"
    assert "not-a-key" not in captured.getvalue()
    assert _normalize_key("  nsec1ex ample\n") == "nsec1example"
    out = io.StringIO()
    err = io.StringIO()
    try:
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            _relay_error("authentication failed: nsec1secret")
    except RelayRejected as exc:
        assert str(exc) == "authentication failed: nsec1<redacted>"
    else:
        raise AssertionError("relay authentication error was swallowed")
    exact = "authentication failed: nsec1<redacted>"
    assert out.getvalue().strip() == exact
    assert err.getvalue().strip() == exact
    assert "nsec1secret" not in out.getvalue()
    assert "[WARNING]" not in out.getvalue()
    success = _success_line("abc", "channel-1", "wss://relay.example.com/")
    assert success == (
        "[SUCCESS] Published event abc to channel channel-1 on wss://relay.example.com/"
    )
    try:
        _relay_url("")
    except PublishError:
        pass
    else:
        raise AssertionError("a missing relay URL was accepted")
    try:
        _relay_url("ws://relay.example.com/")
    except PublishError:
        pass
    else:
        raise AssertionError("an unencrypted relay URL was accepted")
    relay = "wss://relay.example.com/"
    assert _relay_url(relay) == relay
    channel_id = "ab" * 32
    root = note_route(relay, channel_id="", channel_name="")
    assert root.kind == 1 and root.tags == []
    named = note_route(relay, channel_id="", channel_name="ops")
    assert named.kind == 1 and named.tags == [["t", "ops"]]
    channel = note_route(relay, channel_id=channel_id, channel_name="ops")
    assert channel.kind == 1
    assert channel.tags[0] == ["e", channel_id, relay, "root"]
    assert channel.tags[1] == ["h", channel_id]
    assert channel.tags[2] == ["t", "Cloud&Infrastructure"]
    routes = report_routes(relay, channel_id=channel_id, channel_name="ops")
    assert [item.kind for item in routes] == [1, 9]
    assert routes[1].tags == [["h", channel_id], ["t", "Cloud&Infrastructure"]]
    assert format_report("# Title\r\n\r\n- one\r\n- two\r\n") == "# Title\n\n- one\n- two\n"
    for bad_id, bad_name in (
        ("nsec1example", ""),
        ("nostr:nsec1example", ""),
        ("NOSTR:NSEC1EXAMPLE", ""),
        ("", "nostr:nsec1example"),
        ("", "ops nsec1example"),
    ):
        try:
            note_route(relay, channel_id=bad_id, channel_name=bad_name)
        except PublishError:
            pass
        else:
            raise AssertionError("a private key was accepted as a channel id or name")
    short = note_route(relay, channel_id="channel-1", channel_name="")
    assert short.kind == 1 and short.tags[0][1] == "channel-1"
    try:
        note_route(relay, channel_id="bad id", channel_name="")
    except PublishError:
        pass
    else:
        raise AssertionError("a channel id with a space was accepted")
    notes = split_note("line\n" * 40, limit=80)
    assert len(notes) > 1
    assert all(_encoded_len(note) <= 80 for note in notes)
    assert "".join(note.split("\n", 1)[1] for note in notes) == "line\n" * 40
    wide = split_note("😀" * 30, limit=80)
    assert all(_encoded_len(note) <= 80 for note in wide)
    from nostr_sdk import Keys

    keys = Keys.generate()
    from nostr_sdk import ClientBuilder, RelayUrl, SignerAuthenticator

    ClientBuilder().authenticator(SignerAuthenticator(keys)).build()
    asyncio.run(_check_auth_through_local_relay(keys))
    public = keys.public_key().to_hex()
    assert Keys.parse(keys.secret_key().to_hex()).public_key().to_hex() == public
    assert Keys.parse(keys.secret_key().to_bech32()).public_key().to_hex() == public
    # The nsec branch of _load_keys, and its hex re-parse, give the same key.
    assert _load_keys(keys.secret_key().to_bech32()).public_key().to_hex() == public
    assert _load_keys(keys.secret_key().to_hex()).public_key().to_hex() == public
    # A routing value is never the signing key, whatever form it was pasted in.
    secret_hex = keys.secret_key().to_hex()
    for bad_id, bad_name in (
        (secret_hex, ""),
        (secret_hex.upper(), ""),
        ("nostr:" + secret_hex, ""),
        ("", secret_hex),
        ("", "nostr:" + keys.secret_key().to_bech32()),
    ):
        try:
            _build_event(
                "x",
                secret_hex,
                note_route(relay, channel_id=bad_id, channel_name=bad_name),
            )
        except PublishError as exc:
            assert secret_hex not in str(exc).lower()
        else:
            raise AssertionError("the signing key was accepted as a channel id or name")
    event = _build_event(
        "offline",
        keys.secret_key().to_hex(),
        note_route(relay, channel_id=channel_id, channel_name=""),
    )
    assert event.kind().as_u16() == 1
    assert event.content() == "offline"
    tag_rows = [list(tag.to_vec()) for tag in event.tags()]
    assert ["e", channel_id, relay, "root"] in tag_rows
    assert ["h", channel_id] in tag_rows
    assert ["t", "Cloud&Infrastructure"] in tag_rows
    assert ["p", public] in tag_rows
    mention = "11" * 32
    mentioned = _build_event(
        "offline",
        keys.secret_key().to_hex(),
        note_route(relay, channel_id=channel_id, channel_name=""),
        mentions=[mention],
    )
    mentioned_tags = [list(tag.to_vec()) for tag in mentioned.tags()]
    assert ["p", public] in mentioned_tags
    assert ["p", mention] in mentioned_tags
    assert notification_pubkeys("") == []
    assert notification_pubkeys("AB" * 32 + ", " + "cd" * 32) == ["ab" * 32, "cd" * 32]
    try:
        notification_pubkeys("nsec1example")
    except PublishError:
        pass
    else:
        raise AssertionError("a private key was accepted as a mention")
    quiet = _event_tags(
        note_route(relay, channel_id=channel_id, channel_name=""),
        keys,
        [],
    )
    assert ["p", mention] not in quiet
    kind9 = _build_event(
        "# Title\n\n- one\n",
        keys.secret_key().to_hex(),
        routes[1],
    )
    assert kind9.kind().as_u16() == 9
    assert kind9.content() == "# Title\n\n- one\n"
    kind9_tags = [list(tag.to_vec()) for tag in kind9.tags()]
    assert ["e", channel_id, relay, "root"] not in kind9_tags
    assert ["h", channel_id] in kind9_tags
    assert ["p", public] in kind9_tags
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
