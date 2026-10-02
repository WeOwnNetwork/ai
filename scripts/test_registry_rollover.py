#!/usr/bin/env python3
"""registry-rollover.py must do to a render exactly what the template does (fleet#112).

Two routes to the same answer: render every registry-bearing template with the default
registry and with `image_registry=<new>`, then roll the default render over with the
script. Every line the template changes must come out identical. A line the template
leaves alone may be changed only if it is a comment (the template has a few comments that
still name reg.mini.dev or MINIMUS_TOKEN after the switch); those are listed.

    python3 scripts/test_registry_rollover.py            # needs copier>=9 on PATH or $COPIER
"""
from __future__ import annotations

import os
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TOOL = os.path.join(ROOT, "scripts", "registry-rollover.py")
COPIER = os.environ.get("COPIER", "copier")
NEW = ["--data", "image_registry=registry.example.test/weown", "--data", "registry_username=puller"]
COMMON = ["--data", "project_name=ci-render-check", "--data", "domain=ci-render-check.example.test"]
ALLM = [
    "--data", "do_region=atl1", "--data", "droplet_size=s-2vcpu-4gb-amd", "--data", "data_volume_size_gb=50",
    "--data", "infisical_project_id=00000000-0000-4000-8000-000000000000", "--data", "infisical_environment=prod",
    "--data", "infisical_secret_path=/sites/ci-render-check", "--data", "cloudflare_proxied=false",
]
BAO = [
    "--data", "secret_backend=openbao", "--data", "bao_addr=https://bao.example.test:8200",
    "--data", "bao_role_id=00000000-0000-4000-8000-000000000000", "--data", "bao_secret_path=platform/ci-render-check",
    "--data", "bao_cli_sha256=" + "0" * 64,
]
RENDERS = {
    "anythingllm-infisical": ("anythingllm-docker", ALLM + ["--data", "secret_backend=infisical"]),
    "anythingllm-openbao": ("anythingllm-docker", ALLM + BAO),
    "openclaw": ("openclaw-docker", ["--data", 'ssh_source_cidrs=["198.51.100.10/32"]']),
    **{t: (f"{t}-docker", []) for t in
       ("billing", "gitea", "keycloak", "owncloud", "sandbox", "searxng", "signoz", "supabase", "wordpress")},
}


def render(out: str, extra: list[str]) -> None:
    for name, (template, args) in RENDERS.items():
        subprocess.run([COPIER, "copy", "--trust", "--defaults", "--quiet", "--vcs-ref", "HEAD",
                        os.path.join(ROOT, template), os.path.join(out, name), *COMMON, *args, *extra],
                       check=True, stdout=subprocess.DEVNULL)


def git_track(path: str) -> None:
    """The script reads only files git tracks, so the scratch copy becomes a throwaway repo."""
    subprocess.run(["git", "init", "-q", path], check=True)
    subprocess.run(["git", "-C", path, "add", "--force", "--", "."], check=True)   # renders .gitignore some files


def lines_of(path: str) -> list[str] | None:
    try:
        with open(path, encoding="utf-8") as handle:
            return handle.read().splitlines()
    except (UnicodeDecodeError, OSError):
        return None


def compare(default: str, rolled: str, dest: str) -> tuple[int, int, list[str], list[str]]:
    same = 0
    extra: list[str] = []
    wrong: list[str] = []
    template_changes = 0
    for dirpath, _, files in os.walk(default):
        for name in files:
            rel = os.path.relpath(os.path.join(dirpath, name), default)
            a, r, d = (lines_of(os.path.join(base, rel)) for base in (default, rolled, dest))
            if a is None or r is None or d is None:
                continue
            if not (len(a) == len(r) == len(d)):
                wrong.append(f"{rel}: line count differs")
                continue
            for number, (x, y, z) in enumerate(zip(a, r, d), start=1):
                if x != z:
                    template_changes += 1
                    if y == z:
                        same += 1
                    else:
                        wrong.append(f"{rel}:{number}: got {y.strip()!r}, template {z.strip()!r}")
                elif y != x:
                    (extra if y.lstrip().startswith("#") else wrong).append(f"{rel}:{number}: {y.strip()}")
    return template_changes, same, extra, wrong


def main() -> int:
    with tempfile.TemporaryDirectory() as tmp:
        default, rolled, dest = (os.path.join(tmp, n) for n in ("default", "rolled", "dest"))
        render(default, [])
        render(dest, NEW)
        shutil.copytree(default, rolled)
        git_track(rolled)
        run = subprocess.run([sys.executable, TOOL, "--registry", "registry.example.test/weown",
                              "--username", "puller", "--write", rolled], capture_output=True, text=True)
        if run.returncode not in (0, 3):
            print(run.stderr)
            return 1
        changes, same, extra, wrong = compare(default, rolled, dest)
    print(f"template changes {changes} lines; the script matches {same}")
    for item in extra:
        print(f"  comment the template leaves stale, rewritten here: {item}")
    for item in wrong:
        print(f"FAIL {item}")
    if changes == 0:
        print("FAIL: the template changed nothing; is image_registry still a copier answer?")
        return 1
    if wrong or same != changes:
        return 1

    # Direct cases, expected values by hand.
    sys.path.insert(0, os.path.join(ROOT, "scripts"))
    import importlib.util
    spec = importlib.util.spec_from_file_location("rollover", TOOL)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    reg, user = "registry.digitalocean.com/weown", "puller"
    cases = [
        ("image: reg.mini.dev/caddy:2", "image: registry.digitalocean.com/weown/caddy:2"),
        ('argv: [docker, login, "reg.mini.dev", -u, "minimus", --password-stdin]',
         'argv: [docker, login, "registry.digitalocean.com", -u, "puller", --password-stdin]'),
        ('echo "$MINIMUS_TOKEN" | docker login reg.mini.dev --username token --password-stdin',
         'echo "$REGISTRY_TOKEN" | docker login registry.digitalocean.com --username puller --password-stdin'),
        ("WP_IMAGE=reg.mini.dev/1923/wordpress-fluentsmtp:latest",
         "WP_IMAGE=registry.digitalocean.com/weown/1923/wordpress-fluentsmtp:latest"),
        ("- name: Log in to reg.mini.dev", "- name: Log in to registry.digitalocean.com/weown"),
        ("# the minimus username is token", "# the minimus username is token"),  # not a login line
        ("echo $T | docker login --username=token reg.mini.dev --password-stdin",
         "echo $T | docker login --username=puller registry.digitalocean.com --password-stdin"),
        ('argv: [docker, login, "reg.mini.dev", --username, "minimus", --password-stdin]',
         'argv: [docker, login, "registry.digitalocean.com", --username, "puller", --password-stdin]'),
        ("docker login --username token reg.mini.dev --password-stdin && docker pull reg.mini.dev/caddy:2",
         "docker login --username puller registry.digitalocean.com --password-stdin && docker pull registry.digitalocean.com/weown/caddy:2"),
    ]
    bad = [(i, mod.rewrite_line(i, reg, user), o) for i, o in cases if mod.rewrite_line(i, reg, user) != o]
    for i, got, want in bad:
        print(f"FAIL rewrite {i!r}: got {got!r}, want {want!r}")
    # MANUAL cases, each in a throwaway repo. Output names file:line and a kind, never content.
    def roll(files: dict[str, str], untracked: dict[str, str] | None = None, path: str = ".",
             delete: str | None = None) -> tuple[int, str, str]:
        with tempfile.TemporaryDirectory() as tmp:
            for name, body in files.items():
                os.makedirs(os.path.dirname(os.path.join(tmp, name)) or tmp, exist_ok=True)
                with open(os.path.join(tmp, name), "w") as handle:
                    handle.write(body)
            git_track(tmp)
            if delete:
                os.remove(os.path.join(tmp, delete))   # still tracked, gone from disk
            for name, body in (untracked or {}).items():
                with open(os.path.join(tmp, name), "w") as handle:
                    handle.write(body)
            run = subprocess.run([sys.executable, TOOL, "--registry", reg, "--username", user, os.path.join(tmp, path)],
                                 capture_output=True, text=True)
            return run.returncode, run.stdout, run.stderr
    problems = []
    rc, out, err = roll({"login.sh": 'docker login reg.mini.dev -u minimus -p "$MINIMUS_TOKEN"\n'})
    if not (rc == 3 and "password on the docker login command line" in err and "MINIMUS_TOKEN" not in err):
        problems.append(f"argv password not MANUAL (rc {rc}): {err!r}")
    rc, out, err = roll({"versions.tf": "  token = var.minimus_token\n"})
    if not (rc == 3 and "still mentions minimus" in err and "token = var" not in err):
        problems.append(f"renamed variable not MANUAL, or content printed (rc {rc}): {err!r}")
    rc, out, err = roll({"ok.sh": "echo $MINIMUS_TOKEN | docker login --username token reg.mini.dev --password-stdin\n",
                         "tfvars.example": 'minimus_token = "SENTINEL-TRACKED"\n'},
                        untracked={".env": "MINIMUS_TOKEN=SENTINEL-UNTRACKED\nIMAGE=reg.mini.dev/caddy:2\n"})
    want = "+echo $REGISTRY_TOKEN | docker login --username puller registry.digitalocean.com --password-stdin"
    if want not in out.splitlines():
        problems.append(f"login with the server after --username: {out!r}")
    if "SENTINEL" in out + err:
        problems.append("a sentinel value reached the output (untracked file read, or MANUAL printed content)")
    rc, out, err = roll({"argv.yml": 'argv: [docker, login, "reg.mini.dev", -u, "minimus", -p, "$MINIMUS_TOKEN"]\n'})
    if not (rc == 3 and "password on the docker login command line" in err):
        problems.append(f"argv-list -p password not MANUAL (rc {rc}): {err!r}")
    rc, out, err = roll({"u.sh": "echo $T | docker login -u someone reg.mini.dev --password-stdin\n"})
    if not (rc == 3 and "username is not the requested one" in err):
        problems.append(f"a login keeping another username was not MANUAL (rc {rc}): {err!r}")
    rc, out, err = roll({"nouser.sh": "echo $T | docker login reg.mini.dev --password-stdin\n"})
    if not (rc == 3 and "has no --username" in err):
        problems.append(f"a login with no username was not MANUAL (rc {rc}): {err!r}")
    rc, out, err = roll({"a.sh": "image: reg.mini.dev/caddy:2\n", "b.sh": "x\n"}, delete="a.sh")
    if not (rc == 2 and "cannot read" in err):
        problems.append(f"an unreadable tracked file did not stop the run (rc {rc}): {err!r}")
    rc, out, err = roll({"a.sh": "x\n"}, path="no-such-dir")
    if rc != 2:
        problems.append(f"a missing path was not refused (rc {rc})")
    with tempfile.TemporaryDirectory() as tmp:
        def refused_as_registry(bad: str) -> bool:
            run = subprocess.run([sys.executable, TOOL, f"--registry={bad}", "--username", user, tmp],
                                 capture_output=True, text=True)
            return run.returncode == 2 and "--registry must be" in run.stderr
        refused = all(refused_as_registry(bad)
                      for bad in ("reg.mini.dev/x", "reg.mini.dev:443/x", "--config/foo", "a..b/ns", "-a.example/ns",
                                  "a-.example/ns", "Registry.Example/ns", "a.example/ns/", "registry/weown"))
        accepted = subprocess.run([sys.executable, TOOL, "--registry", "registry.digitalocean.com:443/weown-1",
                                   "--username", user, tmp], capture_output=True, text=True).returncode == 2 \
            and "not inside a git checkout" in subprocess.run([sys.executable, TOOL, "--registry", "registry.digitalocean.com:443/weown-1",
                                   "--username", user, tmp], capture_output=True, text=True).stderr
        not_git = subprocess.run([sys.executable, TOOL, "--registry", reg, "--username", user, tmp],
                                 capture_output=True, text=True).returncode == 2
    if not refused:
        problems.append("a malformed --registry (or reg.mini.dev itself) was not refused")
    if not accepted:
        problems.append("a valid host:port/namespace --registry was refused")
    if not not_git:
        problems.append("a directory outside git was not refused")
    for problem in problems:
        print(f"FAIL {problem}")
    if bad or problems:
        return 1
    print(f"ok: {len(cases)} direct cases; MANUAL for an argv password and a renamed variable, content never printed; "
          "untracked files never read; login host in any argument position; bad paths and reg.mini.dev refused")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
