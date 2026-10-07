#!/usr/bin/env bash
# deploy-check.sh — the credential-boundary steps of a site's ansible/deploy.yml, as
# rendered, without a box:
#   1. "Register the runner": its own shell, with stand-in systemctl and docker. It
#      stops and disables the runner unit BEFORE registering (re-registration on a box
#      whose runner is enabled); if that stop fails, nothing registers; with
#      data/.runner present it does nothing.
#   2. the token gate (stop+disable / refuse / enable), under real ansible with the
#      token check's answer mocked: PRESENT=1 and CHECK_FAILED stop, disable and fail;
#      PRESENT=0 enables and starts.
#
#   gitea-runner-docker/tests/deploy-check.sh <site-dir>
# Needs python3 + PyYAML, and ansible-playbook for part 2 (else that part is NOT RUN).
# Exit: 0 pass · 1 mismatch · 2 not run.
set -uo pipefail
SITE=$(cd "${1:?usage: $0 <site-dir>}" && pwd) || exit 2
W=$(mktemp -d)
trap 'find "$W" -delete 2>/dev/null' EXIT
BAD=0
res() { if [ "$1" = "$2" ]; then echo "PASS     $3"; else echo "MISMATCH $3 (expected '$2', got '$1')"; BAD=1; fi; }

# 1. the register task's shell, its app_dir pointed at a scratch dir
python3 - "$SITE/ansible/deploy.yml" "$W/app" > "$W/register.sh" <<'PY' || { echo "NOT RUN: no register task"; exit 2; }
import sys, yaml
play = yaml.safe_load(open(sys.argv[1]))[0]
t = next(t for t in play["tasks"] if t["name"].startswith("Register the runner"))
s = t["ansible.builtin.shell"].replace("{{ app_dir }}", sys.argv[2])
assert "{{" not in s, s
print(s)
PY
mkdir -p "$W/app/data" "$W/bin"
cat > "$W/bin/systemctl" <<'EOF'
#!/bin/sh
echo "systemctl $*" >> "$CALLS"
[ "${SYSTEMCTL_FAILS:-0}" = 1 ] && exit 1
exit 0
EOF
cat > "$W/bin/docker" <<'EOF'
#!/bin/sh
echo "docker $*" >> "$CALLS"
echo '{"id": 7}' > data/.runner
EOF
chmod +x "$W/bin/systemctl" "$W/bin/docker"
export CALLS="$W/calls"
reg() { : > "$CALLS"; rm -f "$W/app/data/.runner"; [ "${1:-}" = registered ] && echo '{"id": 1}' > "$W/app/data/.runner"
  (cd "$W/app" && PATH="$W/bin:$PATH" bash "$W/register.sh" > /dev/null 2>&1); echo $?; }
rc=$(reg)
res "$rc|$(sed 's/ .*//' "$CALLS" | tr '\n' ',')" "0|systemctl,docker," "register: the runner unit is stopped before registering"
res "$(grep -c -- 'disable --now .*-runner.service' "$CALLS")" 1 "register: the unit is disabled and stopped (disable --now)"
rc=$(SYSTEMCTL_FAILS=1 reg)
res "$rc|$(grep -c '^docker' "$CALLS")|$([ -s "$W/app/data/.runner" ] && echo runner || echo none)" "1|0|none" "register: a failed stop registers nothing (fail closed)"
rc=$(reg registered)
res "$rc|$(wc -l < "$CALLS" | tr -d ' ')" "0|0" "register: already registered, it touches nothing"

# 2. the token gate under real ansible
# The dedicated venv first, as scripts/deploy.sh does: a pyenv shim can pass
# `command -v` and still fail when run. Then prove the one we picked actually runs.
ANSIBLE=""
for c in "$HOME/.ansible-venv/bin/ansible-playbook" "$(command -v ansible-playbook 2> /dev/null)"; do
  if [ -n "$c" ] && "$c" --version > /dev/null 2>&1; then ANSIBLE=$c; break; fi
done
if [ -z "$ANSIBLE" ]; then
  echo "NOT RUN: no working ansible-playbook (the token gate)"; exit 2
fi
python3 - "$SITE/ansible/deploy.yml" "$ANSIBLE" "$W" <<'PY' || BAD=1
import pathlib, subprocess, sys, yaml
site_play, ansible, w = sys.argv[1], sys.argv[2], pathlib.Path(sys.argv[3])
play = yaml.safe_load(open(site_play))[0]
names = ["Stop and disable the runner while the registration token is still in Infisical",
         "Refuse to take jobs until the registration token is deleted",
         "Enable and start the runner cycle (the token is gone)"]
tasks = [t for t in play["tasks"] if t["name"] in names]
assert [t["name"] for t in tasks] == names, [t["name"] for t in tasks]
stop = tasks[0]
ok_shape = stop["ansible.builtin.systemd"].get("enabled") is False and "failed_when" not in stop
print(("PASS    " if ok_shape else "MISMATCH"), "gate: the stop task disables the unit and has no failed_when (fails closed)")
bad = not ok_shape
for t in tasks:
    if "ansible.builtin.systemd" in t:
        sd = t.pop("ansible.builtin.systemd")
        t["ansible.builtin.debug"] = {"msg": f"SYSTEMD state={sd['state']} enabled={sd.get('enabled')}"}
for answer, want_fail, want_text, want_sd in [
    ("PRESENT=1", True, "is still in the runner's Infisical project", "SYSTEMD state=stopped enabled=False"),
    ("CHECK_FAILED: infisical export", True, "the token check could not run (CHECK_FAILED: infisical export)", "SYSTEMD state=stopped enabled=False"),
    ("PRESENT=0", False, "SYSTEMD state=started enabled=True", "SYSTEMD state=started enabled=True"),
]:
    test = [{"hosts": "localhost", "gather_facts": False, "connection": "local",
             "tasks": [{"ansible.builtin.set_fact": {"token_gone": {"stdout": answer}}}] + tasks}]
    f = w / "gate.yml"
    f.write_text(yaml.safe_dump(test))
    r = subprocess.run([ansible, "-i", "localhost,", str(f)], capture_output=True, text=True)
    out = r.stdout + r.stderr
    ok = (r.returncode != 0) == want_fail and want_text in out and want_sd in out
    print(("PASS    " if ok else "MISMATCH"), f"gate: {answer} -> {'stop, disable and fail' if want_fail else 'enable and start'}")
    bad = bad or not ok
sys.exit(1 if bad else 0)
PY
exit "$BAD"
