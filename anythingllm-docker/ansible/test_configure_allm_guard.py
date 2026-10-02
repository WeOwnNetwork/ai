"""python3 ansible/test_configure_allm_guard.py (needs ansible-core).

weown-fleet#97: configure-allm.yml must only register MCP servers as spawnMcp
node wrappers; AnythingLLM gives a raw command (uvx/npx) its whole env. This
runs the playbook's REAL set_fact + assert tasks on localhost (no container)."""
import json, pathlib, subprocess, sys, tempfile, yaml

PLAY = yaml.safe_load((pathlib.Path(__file__).parent / "configure-allm.yml").read_text())[0]
TASKS = [t for t in PLAY["tasks"] if t["name"].startswith(("Build desired MCP", "Refuse MCP servers"))]
assert len(TASKS) == 2, [t["name"] for t in TASKS]
VARS = {k: v for k, v in PLAY["vars"].items() if k in ("searxng_url", "default_mcp_servers", "extra_mcp_servers")}


def run(extra):
    play = [{"hosts": "localhost", "connection": "local", "gather_facts": False, "vars": VARS, "tasks": TASKS}]
    with tempfile.NamedTemporaryFile("w", suffix=".yml") as f:
        yaml.safe_dump(play, f)
        r = subprocess.run(["ansible-playbook", "-i", "localhost,", f.name, "-e", json.dumps(extra)],
                           capture_output=True, text=True)
    return r.returncode, r.stdout + r.stderr


wrapper = {"command": "node", "args": ["/app/server/storage/mcp/fmcp-weown/index.js"]}
cases = [
    ("defaults (searxng wrapper)", {}, 0),
    ("extra spawnMcp wrapper", {"extra_mcp_servers": {"fmcp": wrapper}}, 0),
    ("extra raw npx", {"extra_mcp_servers": {"fmcp": {"command": "npx", "args": ["-y", "x@latest"],
                                                      "env": {"PW": "do-not-log"}}}}, 2),
    ("searxng overridden to raw uvx", {"extra_mcp_servers": {"searxng": {"command": "uvx", "args": ["mcp-searxng"]}}}, 2),
]
bad = []
for name, extra, want in cases:
    rc, out = run(extra)
    if rc != want or "do-not-log" in out:
        bad.append(f"{name}: rc={rc} want {want}\n{out[-800:]}")
print("\n".join(bad) or f"test_configure_allm_guard: ok ({len(cases)} cases)")
sys.exit(1 if bad else 0)
