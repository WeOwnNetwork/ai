#!/usr/bin/env python3
"""Silent Windows notification repair for Buzz Desktop.

Upstream: https://github.com/block/buzz/issues/2445
On Windows, tauri-plugin-notification stamps Notification.permission as
"denied" at every cold start. Buzz then auto-flips desktopEnabled=false, so
real DM / @mention toasts never fire. Calling new Notification() from this
repair path is WRONG — it produces fake startup toasts and still leaves the
app's mention pipeline disabled.

This script:
  1. Intercepts window.Notification so Buzz always reads permission "granted"
  2. Calls requestPermission() silently (no toast)
  3. Restores desktopEnabled in localStorage
  4. Reloads ONCE so React never sees the false denial
Never show a test toast. Never loop-reload.
"""
from __future__ import annotations

import json
import sys
import time
import urllib.request

try:
    import websocket
except ImportError:
    import subprocess

    subprocess.check_call(
        [sys.executable, "-m", "pip", "install", "websocket-client", "-q"]
    )
    import websocket

CDP = "http://127.0.0.1:9222/json"

# Runs at document-start on the next load, before Tauri's shim and Buzz JS.
INTERCEPTOR = r"""
(function () {
  if (window.__weownBuzzNotifIntercept) return;
  window.__weownBuzzNotifIntercept = true;

  function wrap(Orig) {
    if (!Orig || Orig.__weownBuzzWrapped) return Orig;
    function PatchedNotification(title, options) {
      return new Orig(title, options);
    }
    PatchedNotification.__weownBuzzWrapped = true;
    try { Object.setPrototypeOf(PatchedNotification, Orig); } catch (e) {}
    PatchedNotification.prototype = Orig.prototype;
    if (typeof Orig.requestPermission === "function") {
      PatchedNotification.requestPermission = function () {
        try {
          return Promise.resolve(Orig.requestPermission.apply(Orig, arguments))
            .then(function () { return "granted"; })
            .catch(function () { return "granted"; });
        } catch (e) {
          return Promise.resolve("granted");
        }
      };
    }
    Object.defineProperty(PatchedNotification, "permission", {
      configurable: true,
      enumerable: true,
      get: function () { return "granted"; },
      set: function () { /* ignore tauri shim assigning "denied" */ }
    });
    try {
      if (typeof Orig.requestPermission === "function") {
        void Orig.requestPermission();
      }
    } catch (e) {}
    return PatchedNotification;
  }

  var current = wrap(window.Notification);
  try {
    Object.defineProperty(window, "Notification", {
      configurable: true,
      enumerable: true,
      get: function () { return current; },
      set: function (v) { current = wrap(v); }
    });
  } catch (e) {
    window.Notification = current;
  }
})();
"""

ENABLE_SETTINGS = r"""
(async () => {
  const out = { steps: [] };
  try {
    try { void localStorage.length; } catch (e) {
      return JSON.stringify({ error: "localStorage:" + String(e) });
    }
    if (!String(location.href).includes("tauri.localhost")) {
      return JSON.stringify({ error: "wrong-href:" + location.href });
    }
    if (window.Notification && typeof window.Notification.requestPermission === "function") {
      const before = String(window.Notification.permission);
      let after = before;
      try { after = String(await window.Notification.requestPermission()); } catch (e) {
        out.steps.push("requestErr:" + String(e));
      }
      out.steps.push("perm:" + before + "->" + after);
    } else {
      out.steps.push("no-requestPermission");
    }
    let keys = 0;
    for (let i = 0; i < localStorage.length; i++) {
      const k = localStorage.key(i);
      if (!(k && k.startsWith("buzz-notification-settings.v2:"))) continue;
      const s = JSON.parse(localStorage.getItem(k) || "{}");
      s.desktopEnabled = true;
      s.homeBadgeEnabled = true;
      if (!s.slotAlertsEnabled) s.slotAlertsEnabled = {};
      s.slotAlertsEnabled.mention = true;
      s.slotAlertsEnabled.dm = true;
      s.slotAlertsEnabled.thread_reply = true;
      localStorage.setItem(k, JSON.stringify(s));
      keys++;
    }
    out.enabledKeys = keys;
    out.href = location.href;
    out.intercept = !!window.__weownBuzzNotifIntercept;
    out.permNow = window.Notification ? String(window.Notification.permission) : "missing";
    return JSON.stringify(out);
  } catch (e) {
    return JSON.stringify({ error: String(e) });
  }
})()
"""


def tabs():
    return json.load(urllib.request.urlopen(CDP))


def wait_page(timeout=90):
    deadline = time.time() + timeout
    last = None
    while time.time() < deadline:
        try:
            for t in tabs():
                if "tauri.localhost" not in (t.get("url") or ""):
                    continue
                ws = websocket.create_connection(t["webSocketDebuggerUrl"], timeout=10)
                try:
                    mid = {"n": 1}
                    rpc(ws, "Runtime.enable", mid)
                    probe = rpc(
                        ws,
                        "Runtime.evaluate",
                        mid,
                        {
                            "expression": "(() => { try { return {ok:true, n:localStorage.length, href:location.href}; } catch(e) { return {ok:false, err:String(e)}; } })()",
                            "returnByValue": True,
                        },
                    )
                finally:
                    ws.close()
                val = (
                    (probe.get("result") or {})
                    .get("result", {})
                    .get("value")
                    or {}
                )
                last = val
                if val.get("ok"):
                    return t
        except Exception as e:
            last = {"err": str(e)}
        time.sleep(0.4)
    raise SystemExit("Buzz page not ready: %s" % last)


def rpc(ws, method, mid, params=None):
    payload = {"id": mid["n"], "method": method, "params": params or {}}
    mid["n"] += 1
    ws.send(json.dumps(payload))
    while True:
        data = json.loads(ws.recv())
        if data.get("id") == payload["id"]:
            return data


def eval_async(ws, mid, expression):
    data = rpc(
        ws,
        "Runtime.evaluate",
        mid,
        {
            "expression": expression,
            "awaitPromise": True,
            "returnByValue": True,
        },
    )
    if data.get("error") or (data.get("result") or {}).get("exceptionDetails"):
        return {"cdpError": data}
    remote = (data.get("result") or {}).get("result") or {}
    val = remote.get("value")
    if isinstance(val, str):
        try:
            return json.loads(val)
        except json.JSONDecodeError:
            return {"raw": val}
    return val if val is not None else {"emptyRemote": remote}


def main():
    page = wait_page()
    ws = websocket.create_connection(page["webSocketDebuggerUrl"], timeout=20)
    mid = {"n": 1}
    rpc(ws, "Runtime.enable", mid)
    rpc(ws, "Page.enable", mid)
    rpc(ws, "Page.addScriptToEvaluateOnNewDocument", mid, {"source": INTERCEPTOR})
    # Wrap the already-loaded Notification too (this navigation).
    rpc(ws, "Runtime.evaluate", mid, {"expression": INTERCEPTOR, "returnByValue": True})
    first = eval_async(ws, mid, ENABLE_SETTINGS)
    rpc(ws, "Page.reload", mid, {"ignoreCache": False})
    ws.close()

    time.sleep(1.5)
    page2 = wait_page()
    ws2 = websocket.create_connection(page2["webSocketDebuggerUrl"], timeout=20)
    mid2 = {"n": 1}
    rpc(ws2, "Runtime.enable", mid2)
    rpc(ws2, "Page.enable", mid2)
    rpc(ws2, "Page.addScriptToEvaluateOnNewDocument", mid2, {"source": INTERCEPTOR})
    rpc(ws2, "Runtime.evaluate", mid2, {"expression": INTERCEPTOR, "returnByValue": True})
    second = eval_async(ws2, mid2, ENABLE_SETTINGS)
    ws2.close()

    report = {"first": first, "afterReload": second}
    print(json.dumps(report))
    after = second if isinstance(second, dict) else {}
    if after.get("error"):
        raise SystemExit("repair failed: %s" % after)
    if after.get("permNow") not in ("granted", None) and after.get("cdpError"):
        raise SystemExit("repair failed: %s" % after)


if __name__ == "__main__":
    main()
