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

It never reads, prints or moves a secret. What it cannot rewrite safely is listed as
MANUAL with file:line, and the exit code is 3 while any remains: a renamed variable in
a hand-edited render (`minimus_token`), a token on a command line, or a mention it does
not recognise. Exit 0 means the files changed here mention reg.mini.dev and Minimus
nowhere else.
"""
from __future__ import annotations

import argparse
import difflib
import os
import re
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
# The username given to `docker login` on the same line.
_LOGIN_USER = [
    re.compile(r"(--username )(?:token|minimus)\b"),
    re.compile(r"(-u )(?:token|minimus)\b"),
    re.compile(r"(-u, \")(?:token|minimus)(\")"),
]
_RESIDUE = re.compile(r"reg\.mini\.dev|minimus", re.IGNORECASE)
# Words that legitimately keep "minimus" after a rollover (a feature flag's name).
_KEEP = re.compile(r"use_minimus_registry")
_SKIP_DIRS = {".git", "node_modules", ".terraform", "__pycache__"}


def rewrite_line(line: str, registry: str, username: str) -> str:
    host = registry.split("/", 1)[0]
    login = "docker login" in line or "[docker, login" in line
    for pattern in _LOGIN_HOST:
        line = pattern.sub(lambda m: m.group(1) + host + (m.group(2) if m.lastindex and m.lastindex >= 2 else ""), line)
    if login:
        for pattern in _LOGIN_USER:
            line = pattern.sub(lambda m: m.group(1) + username + (m.group(2) if m.lastindex and m.lastindex >= 2 else ""), line)
    line = line.replace(OLD, registry)
    return line.replace("MINIMUS_TOKEN", "REGISTRY_TOKEN")


def residue(line: str) -> bool:
    return bool(_RESIDUE.search(_KEEP.sub("", line)))


def text_files(paths: list[str]):
    for root in paths:
        if os.path.isfile(root):
            yield root
            continue
        for dirpath, dirnames, filenames in os.walk(root):
            dirnames[:] = sorted(d for d in dirnames if d not in _SKIP_DIRS)
            for name in sorted(filenames):
                yield os.path.join(dirpath, name)


def read_text(path: str) -> str | None:
    try:
        with open(path, encoding="utf-8", newline="") as handle:
            return handle.read()
    except (UnicodeDecodeError, OSError):
        return None


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--registry", required=True, help="new image_registry, e.g. registry.digitalocean.com/weown")
    parser.add_argument("--username", required=True, help="new registry_username for docker login")
    parser.add_argument("--write", action="store_true", help="apply the change (default: print a diff)")
    parser.add_argument("paths", nargs="+")
    args = parser.parse_args(argv)
    if not re.fullmatch(r"[a-z0-9.-]+(:[0-9]+)?(/[a-z0-9._-]+)*", args.registry) or OLD in args.registry:
        parser.error("--registry must be a lower-case registry host with an optional /namespace, and not reg.mini.dev")
    if not re.fullmatch(r"[A-Za-z0-9._@-]+", args.username):
        parser.error("--username must be a plain registry user name")

    changed_files = changed_lines = 0
    manual: list[str] = []
    for path in text_files(args.paths):
        before = read_text(path)
        if before is None or (OLD not in before and "MINIMUS_TOKEN" not in before and not _RESIDUE.search(before)):
            continue
        lines = before.splitlines(keepends=True)
        after_lines = [rewrite_line(line, args.registry, args.username) for line in lines]
        for number, line in enumerate(after_lines, start=1):
            if residue(line):
                manual.append(f"{path}:{number}: {line.strip()}")
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
