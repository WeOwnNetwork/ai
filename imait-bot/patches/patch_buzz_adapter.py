#!/usr/bin/env python3
"""Patch Hermes 0.20.6 Buzz adapter in the image.

Fixes applied at build time (upstream still on this digest):
1. Pass ``--mention <self pubkey>`` on send so unresolved @tokens in replies
   are presentation-only instead of failing the whole publish (Hermes #78797).
2. Watch home_channel when BUZZ_CHANNELS is empty, instead of every listed
   channel (empty watch-set blew Buzz WS quota and looked like a session crash).
3. Honour relay ``retry in Ns`` and do not reset WS backoff until a frame
   arrives, so a quota CLOSED cannot 1s-storm the relay.
4. Treat dotted / compact display-name aliases as inbound mentions so
   ``@i.MAIT.bot`` / ``@iMAIT`` both wake the agent.
"""
from __future__ import annotations

from pathlib import Path

P = Path("/opt/hermes/plugins/platforms/buzz/adapter.py")
text = P.read_text()
orig = text


def must_replace(old: str, new: str, label: str) -> None:
    global text
    if old not in text:
        raise SystemExit(f"patch anchor not found: {label}")
    text = text.replace(old, new, 1)


must_replace(
    """        args = ["messages", "send", "--channel", str(chat_id), "--content", "-"]
        reply_target = reply_to or (metadata or {}).get("thread_id")
        if reply_target:
            args += ["--reply-to", str(reply_target)]
        code, out, err = await self._run_cli(args, input_text=content)
""",
    """        args = ["messages", "send", "--channel", str(chat_id), "--content", "-"]
        reply_target = reply_to or (metadata or {}).get("thread_id")
        if reply_target:
            args += ["--reply-to", str(reply_target)]
        # Explicit identity: unresolved @tokens become presentation-only (#78797).
        if getattr(self, "_self_pubkey", ""):
            args += ["--mention", self._self_pubkey]
        code, out, err = await self._run_cli(args, input_text=content)
""",
    "send() --mention",
)

must_replace(
    """            if reply_to:
                args += ["--reply-to", str(reply_to)]
            code, out, err = await self._run_cli(args, input_text=caption or "")
""",
    """            if reply_to:
                args += ["--reply-to", str(reply_to)]
            if getattr(self, "_self_pubkey", ""):
                args += ["--mention", self._self_pubkey]
            code, out, err = await self._run_cli(args, input_text=caption or "")
""",
    "send_image() --mention",
)

must_replace(
    """        watch = self.channels or list(self._channel_names)
        if not watch:
""",
    """        if self.channels:
            watch = self.channels
        elif self.home_channel:
            watch = [self.home_channel]
        else:
            watch = list(self._channel_names)
        if not watch:
""",
    "watch home_channel fallback",
)

must_replace(
    """                        subscriptions = await self._subscribe_websocket(websocket)
                        self._ws_active = True
                        if self._ws_ready is not None:
                            self._ws_ready.set()
                        backoff = 1.0
                        async for raw in websocket:
""",
    """                        subscriptions = await self._subscribe_websocket(websocket)
                        self._ws_active = True
                        if self._ws_ready is not None:
                            self._ws_ready.set()
                        async for raw in websocket:
                            backoff = 1.0
""",
    "ws backoff reset after frame",
)

must_replace(
    """                except Exception as e:
                    self._ws_active = False
                    logger.warning("Buzz: WebSocket disconnected; retrying in %.1fs: %s", backoff, e)
                    await asyncio.sleep(backoff)
                    backoff = min(backoff * 2, 30.0)
""",
    """                except Exception as e:
                    self._ws_active = False
                    msg = str(e)
                    quota_wait = re.search(r"retry in (\\d+)s", msg)
                    wait = float(quota_wait.group(1)) if quota_wait else backoff
                    wait = max(wait, backoff)
                    logger.warning("Buzz: WebSocket disconnected; retrying in %.1fs: %s", wait, e)
                    await asyncio.sleep(wait)
                    backoff = min(max(backoff, wait) * 2, 30.0)
""",
    "ws quota retry-in",
)

must_replace(
    """    def _is_mentioned(self, content: str) -> bool:
        \"\"\"True when the message addresses this agent (npub, hex, or name).\"\"\"
        lowered = content.lower()
        if self._self_pubkey and self._self_pubkey in lowered:
            return True
        if self._self_npub and self._self_npub in lowered:
            return True
        if self._display_name:
            pattern = rf"(?<!\\w)@?{re.escape(self._display_name.lower())}(?!\\w)"
            if re.search(pattern, lowered):
                return True
        return False
""",
    """    def _mention_names(self) -> list:
        names = []
        if self._display_name:
            names.append(self._display_name.lower())
        bot_name = (os.getenv("HERMES_BOT_NAME") or "").strip().lower()
        if bot_name:
            names.append(bot_name)
        names.extend(["i.mait.bot", "imait", "imait.bot", "i-mait-bot"])
        out, seen = [], set()
        for name in names:
            if name and name not in seen:
                seen.add(name)
                out.append(name)
            compact = re.sub(r"[._-]+", "", name)
            if compact and compact not in seen:
                seen.add(compact)
                out.append(compact)
        return out

    def _is_mentioned(self, content: str) -> bool:
        \"\"\"True when the message addresses this agent (npub, hex, or name).\"\"\"
        lowered = content.lower()
        if self._self_pubkey and self._self_pubkey in lowered:
            return True
        if self._self_npub and self._self_npub in lowered:
            return True
        if "nostr:" in lowered and self._self_npub and self._self_npub.lower() in lowered:
            return True
        for name in self._mention_names():
            pattern = rf"(?<!\\w)@?{re.escape(name)}(?!\\w)"
            if re.search(pattern, lowered):
                return True
        return False
""",
    "_is_mentioned aliases",
)

must_replace(
    """        candidates = []
        if self._display_name:
            candidates.append(re.escape(self._display_name))
        if self._self_npub:
            candidates.append(re.escape(self._self_npub))
        if self._self_pubkey:
            candidates.append(re.escape(self._self_pubkey))
""",
    """        candidates = [re.escape(n) for n in self._mention_names()]
        if self._self_npub:
            candidates.append(re.escape(self._self_npub))
        if self._self_pubkey:
            candidates.append(re.escape(self._self_pubkey))
""",
    "_strip_mention aliases",
)

if text == orig:
    raise SystemExit("patch produced no changes")
P.write_text(text)
print("patched", P)
