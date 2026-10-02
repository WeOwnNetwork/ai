#!/usr/bin/env python3
"""Move a committed site render off reg.mini.dev, the same way the template does.

    scripts/registry-rollover.py --registry registry.example.test/weown --username puller SITE_DIR...
    scripts/registry-rollover.py ... --write SITE_DIR...      # apply; default is a dry run (diff)

reg.mini.dev shuts down on 2026-10-22 (WeOwnDev/weown-fleet#112). The templates take the
registry as one copier answer (`image_registry`, #265), but the committed renders under
`*-docker/sites/` predate it and are rolled over one site at a time. This applies the
template's own rule to a render, so a rolled-over site matches what a fresh render with
`image_registry=<registry>` would contain:

- an image ref `reg.mini.dev/<path>` becomes `<registry>/<path>`, and other mentions of the
  registry become `<registry>`;
- `docker login` takes the registry HOST only (Docker keys credentials by host), with
  `--username <username>`;
- the pull-token key `MINIMUS_TOKEN` becomes `REGISTRY_TOKEN`.

It reads only files git TRACKS (a committed render), never an untracked or ignored one
such as a `.env` or `terraform.tfvars`, and MANUAL lines name file:line and the matched
word, never the line's content. What it cannot rewrite safely is MANUAL, and the exit
code is 3 while any remains: a renamed variable in a hand-edited render
(`minimus_token`), a password on a `docker login` command line, or a mention it does
not recognise. Exit 0 means the tracked files given mention reg.mini.dev and Minimus
nowhere else. A path that does not exist, or holds no tracked file, is exit 2.
"""
from __future__ import annotations

import argparse
import difflib
import os
import re
import subprocess
import sys

OLD = "reg.mini.dev"
_REF = re.escape(OLD)
# Contexts that name the registry HOST, not the namespace: what `docker login` is given.
_LOGIN_HOST = [
    re.compile(r"(docker login )" + _REF + r"\b"),
    re.compile(r"(\[docker, login, \")" + _REF + r"(\")"),
    re.compile(r"(Authenticate Docker to `)" + _REF + r"(`)"),
    re.compile(r"(Log Docker into `)" + _REF + r"(`)"),
]
# A password given on the `docker login` command line, not --password-stdin: shell forms
# (`-p x`, `--password=x`) and argv-list forms (`-p, "x"`, `"--password", "x"`).
_LOGIN_ARGV_PASSWORD = re.compile(r"(?:^|[\s\[,])\"?(?:-p|--password)\"?(?:[\s,=]|$)")
# The username given to `docker login` on the same line: shell (`-u x`, `--username x`,
# `--username=x`) and argv-list (`-u, "x"`, `--username, "x"`) forms.
_LOGIN_USER = [
    re.compile(r"(--username[ =]\"?)(?:token|minimus)\b"),
    re.compile(r"(-u \"?)(?:token|minimus)\b"),
    re.compile(r"((?:-u|--username), \")(?:token|minimus)(\")"),
]
# Any username option on a login line, to check that the requested user ended up there.
_LOGIN_ANY_USER = re.compile(r"(?:--username[ =]|-u |(?:-u|--username), )\"?([^\s\",\]]+)")
# A registry host: DNS labels (no empty or dash-edged label), optional port; then namespaces.
_REGISTRY = re.compile(r"(?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?)(?:\.[a-z0-9](?:[a-z0-9-]*[a-z0-9])?)*(?::[0-9]+)?"
                       r"(?:/[a-z0-9]+(?:[._-][a-z0-9]+)*)*")
_RESIDUE = re.compile(r"reg\.mini\.dev|minimus", re.IGNORECASE)
# Words that legitimately keep "minimus" after a rollover (a feature flag's name).
_KEEP = re.compile(r"use_minimus_registry")


# A `docker login` COMMAND (options or the server follow it), not prose such as
# "Optional docker login for private registry (reg.mini.dev)".
_LOGIN_COMMAND = re.compile(r"docker login\s+(?:-|" + _REF + r"\b)|\[docker, login,")


def is_login(line: str) -> bool:
    return bool(_LOGIN_COMMAND.search(line))


def rewrite_line(line: str, registry: str, username: str) -> str:
    host = registry.split("/", 1)[0]
    login = is_login(line)   # decided on the ORIGINAL line, before the host is replaced
    for pattern in _LOGIN_HOST:
        line = pattern.sub(lambda m: m.group(1) + host + (m.group(2) if m.lastindex and m.lastindex >= 2 else ""), line)
    if login:
        for pattern in _LOGIN_USER:
            line = pattern.sub(lambda m: m.group(1) + username + (m.group(2) if m.lastindex and m.lastindex >= 2 else ""), line)
        # `docker login` takes a HOST wherever the server argument sits; an image ref
        # (reg.mini.dev/<path>) on the same line keeps its namespace.
        line = line.replace(OLD + "/", registry + "/")
        line = re.sub(_REF + r"\b", host, line)
    line = line.replace(OLD, registry)
    return line.replace("MINIMUS_TOKEN", "REGISTRY_TOKEN")


def manual_reason(before: str, after: str, username: str = "") -> str | None:
    """Why a line needs a human, by kind only: never the line's content."""
    if is_login(before) and _LOGIN_ARGV_PASSWORD.search(before):
        return "password on the docker login command line"
    if is_login(before) and username:
        users = _LOGIN_ANY_USER.findall(after)
        if users and any(user != username for user in users):
            return "docker login username is not the requested one"
    match = _RESIDUE.search(_KEEP.sub("", after))
    return f"still mentions {match.group(0)}" if match else None


def _refuse(message: str) -> None:
    print(f"registry-rollover: {message}", file=sys.stderr)
    raise SystemExit(2)


def tracked_files(paths: list[str]) -> list[str]:
    """Files git tracks under each path. An untracked or ignored file is never read."""
    files: list[str] = []
    for root in paths:
        absroot = os.path.realpath(root)   # git reports a resolved toplevel (macOS /var -> /private/var)
        if not os.path.exists(absroot):
            _refuse(f"{root}: no such file or directory")
        here = absroot if os.path.isdir(absroot) else os.path.dirname(absroot)
        top = subprocess.run(["git", "-C", here, "rev-parse", "--show-toplevel"], capture_output=True, text=True)
        if top.returncode != 0:
            _refuse(f"{root}: not inside a git checkout (only committed renders are read)")
        top_dir = top.stdout.strip()
        listing = subprocess.run(["git", "-C", top_dir, "ls-files", "-z", "--", os.path.relpath(absroot, top_dir)],
                                 capture_output=True, text=True)
        listed = [os.path.join(top_dir, name) for name in listing.stdout.split("\0") if name]
        if listing.returncode != 0 or not listed:
            _refuse(f"{root}: git tracks no file here")
        files.extend(listed)
        others = subprocess.run(["git", "-C", top_dir, "ls-files", "-z", "--others", "--", os.path.relpath(absroot, top_dir)],
                                capture_output=True, text=True).stdout.split("\0")
        others = [name for name in others if name]
        if others:
            shown = ", ".join(others[:8]) + (" ..." if len(others) > 8 else "")
            print(f"NOT READ: {len(others)} untracked or ignored file(s) under {root} (check them yourself): {shown}",
                  file=sys.stderr)
    return files


def read_text(path: str) -> str | None:
    """The file's text; None only for a binary file. An I/O error stops the run (exit 2):
    a tracked file that cannot be read means the render was not fully checked."""
    try:
        with open(path, encoding="utf-8", newline="") as handle:
            return handle.read()
    except UnicodeDecodeError:
        return None
    except OSError as exc:
        _refuse(f"{os.path.relpath(path)}: cannot read ({type(exc).__name__}); the render was not fully checked")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--registry", required=True, help="new image_registry, e.g. registry.digitalocean.com/weown")
    parser.add_argument("--username", required=True, help="new registry_username for docker login")
    parser.add_argument("--write", action="store_true", help="apply the change (default: print a diff)")
    parser.add_argument("paths", nargs="+")
    args = parser.parse_args(argv)
    if not _REGISTRY.fullmatch(args.registry) or args.registry.split("/", 1)[0].split(":", 1)[0] == OLD:
        parser.error("--registry must be a lower-case registry host with an optional /namespace, and not reg.mini.dev")
    if not re.fullmatch(r"[A-Za-z0-9._@-]+", args.username):
        parser.error("--username must be a plain registry user name")

    changed_files = changed_lines = 0
    manual: list[str] = []
    for path in tracked_files(args.paths):
        before = read_text(path)
        if before is None or (OLD not in before and "MINIMUS_TOKEN" not in before and not _RESIDUE.search(before)):
            continue
        lines = before.splitlines(keepends=True)
        after_lines = [rewrite_line(line, args.registry, args.username) for line in lines]
        for number, (old_line, new_line) in enumerate(zip(lines, after_lines), start=1):
            reason = manual_reason(old_line, new_line, args.username)
            if reason:
                manual.append(f"{os.path.relpath(path)}:{number}: {reason}")
        if after_lines == lines:
            continue
        changed_files += 1
        changed_lines += sum(1 for a, b in zip(lines, after_lines) if a != b)
        if args.write:
            with open(path, "w", encoding="utf-8", newline="") as handle:
                handle.writelines(after_lines)
        else:
            sys.stdout.writelines(difflib.unified_diff(lines, after_lines, path, path))

    verb = "rewrote" if args.write else "would rewrite"
    print(f"{verb} {changed_lines} lines in {changed_files} files", file=sys.stderr)
    if manual:
        print(f"MANUAL: {len(manual)} lines still mention reg.mini.dev or Minimus:", file=sys.stderr)
        for item in manual:
            print(f"  {item}", file=sys.stderr)
        return 3
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
