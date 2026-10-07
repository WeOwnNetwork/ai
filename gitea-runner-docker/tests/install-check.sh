#!/usr/bin/env bash
# install-check.sh — cloud-init's pinned installs, for real, in Ubuntu 24.04:
#   - install-docker.sh downloads Docker's real apt key and accepts it (exactly one
#     primary key, the pinned fingerprint), then asks apt for the pinned versions;
#   - MUTANT: the same key with a second primary key appended is refused before any
#     keyring or apt source is written (signed-by would trust both keys);
#   - MUTANT: a wrong pinned fingerprint is refused the same way;
#   - install-infisical.sh accepts the real release .deb against its pinned sha256,
#     and refuses a wrong sha256 before installing.
# The script is the one terraform would render (tofu templatefile, synthetic values).
# apt-get, apt-mark and systemctl are stand-ins that record their arguments; curl,
# gpg and sha256sum are real. Native platform: nothing here is installed, so the
# architecture does not matter, and emulation would only make it slow.
#
#   gitea-runner-docker/tests/install-check.sh <site-dir>
# Needs tofu, docker and the network. Exit: 0 pass · 1 mismatch · 2 not run.
set -uo pipefail
SITE=$(cd "${1:?usage: $0 <site-dir>}" && pwd) || exit 2
if ! command -v tofu > /dev/null || ! command -v docker > /dev/null; then echo "NOT RUN: needs tofu and docker"; exit 2; fi
W=$(mktemp -d)
trap 'find "$W" -delete 2>/dev/null' EXIT
BAD=0
res() { if [ "$1" = "$2" ]; then echo "PASS     $3"; else echo "MISMATCH $3 (expected '$2', got '$1')"; BAD=1; fi; }

printf 'templatefile("%s/terraform/templates/cloud-init.yaml", {project_name="weown_ci_runner", infisical_client_id="c", infisical_client_secret="s", infisical_project_id="p", infisical_environment="prod"})\n' "$SITE" \
  | (cd "$W" && tofu console) > "$W/raw.txt" 2>&1
python3 - "$W" <<'PY' || { echo "NOT RUN: could not render the site's cloud-init"; exit 2; }
import pathlib, re, sys, yaml
W = pathlib.Path(sys.argv[1])
text = re.search(r'<<EOT\n(.*)\nEOT', (W / "raw.txt").read_text(), re.S).group(1)
files = {f["path"]: f["content"] for f in yaml.safe_load(text)["write_files"]}
(W / "docker.sh").write_text(files["/tmp/install-docker.sh"])
(W / "infisical.sh").write_text(files["/tmp/install-infisical.sh"])
PY
# Mutants, each an exact edit that must apply.
sed 's#-o /etc/apt/keyrings/docker.asc.new$#-o /etc/apt/keyrings/docker.asc.new \&\& cp /bundle.asc /etc/apt/keyrings/docker.asc.new#' "$W/docker.sh" > "$W/docker-twokeys.sh"
sed 's/^FPR=9/FPR=8/' "$W/docker.sh" > "$W/docker-wrongfpr.sh"
sed 's/^SHA256=c/SHA256=d/' "$W/infisical.sh" > "$W/infisical-wrongsha.sh"
for m in docker-twokeys docker-wrongfpr infisical-wrongsha; do
  cmp -s "$W/${m%%-*}.sh" "$W/$m.sh" && { echo "NOT RUN: mutant $m did not apply"; exit 2; }
done
# The attack shape: ONE armored file holding Docker's real key AND a second primary key
# (Tailscale's, as a stand-in for an attacker's), exported together.
if ! curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o "$W/docker.key" \
  || ! curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/noble.noarmor.gpg -o "$W/extra.key"; then
  echo "NOT RUN: could not fetch the keys"; exit 2
fi
mkdir -m 700 "$W/gnupg"
GNUPGHOME="$W/gnupg" gpg -q --import "$W/docker.key" "$W/extra.key" 2> /dev/null
GNUPGHOME="$W/gnupg" gpg -q --armor --export > "$W/bundle.asc"
[ "$(gpg --show-keys --with-colons "$W/bundle.asc" | grep -c '^pub')" = 2 ] || { echo "NOT RUN: the bundle does not hold two primary keys"; exit 2; }
mkdir -p "$W/stubs"
for c in apt-get apt-mark systemctl; do
  printf '#!/bin/sh\necho "%s $*" >> /w/calls\n' "$c" > "$W/stubs/$c"; chmod +x "$W/stubs/$c"
done

run() { # script -> "rc|keyring|source|apt-install-line"
  docker run --rm -v "$W:/w" -v "$W/bundle.asc:/bundle.asc:ro" ubuntu:24.04 bash -c '
    apt-get update -qq > /dev/null && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq curl ca-certificates gnupg > /dev/null 2>&1
    : > /w/calls
    PATH=/w/stubs:$PATH bash /w/'"$1"' > /w/out 2>&1; rc=$?
    k=$( { [ -f /etc/apt/keyrings/docker.asc ] && echo keyring; } || echo nokeyring)
    s=$( { [ -f /etc/apt/sources.list.d/docker.list ] && echo source; } || echo nosource)
    i=$(grep -c "apt-get install" /w/calls)
    echo "$rc|$k|$s|$i"' 2>&1 | tail -n 1
}
res "$(run docker.sh)" "0|keyring|source|1" "Docker's real key accepted (one primary key, the pinned fingerprint), apt asked to install"
res "$(grep -c 'apt-get install -y -qq docker-ce=5:.* docker-ce-cli=5:.* containerd.io=.* docker-compose-plugin=' "$W/calls")" 1 "the apt install names exact versions of all four packages"
res "$(run docker-twokeys.sh)" "1|nokeyring|nosource|0" "MUTANT a second primary key: refused, no keyring, no source, nothing installed"
res "$(run docker-wrongfpr.sh)" "1|nokeyring|nosource|0" "MUTANT a wrong pinned fingerprint: refused the same way"
inf() { # script -> "rc|apt-install-called"
  docker run --rm -v "$W:/w" ubuntu:24.04 bash -c '
    apt-get update -qq > /dev/null && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq curl ca-certificates > /dev/null 2>&1
    : > /w/calls
    PATH=/w/stubs:$PATH bash /w/'"$1"' > /w/out 2>&1; rc=$?
    echo "$rc|$(grep -c "apt-get install" /w/calls)"' 2>&1 | tail -n 1
}
res "$(inf infisical.sh | cut -d'|' -f2)" 1 "the real Infisical .deb matches its pinned sha256 and goes to apt"
res "$(inf infisical-wrongsha.sh)" "1|0" "MUTANT a wrong sha256: refused before apt"
exit "$BAD"
