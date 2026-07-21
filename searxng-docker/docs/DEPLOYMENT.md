# SearXNG Deployment Notes

## Secret Key Handling

Do not commit the real SearXNG `server.secret_key` value.

The production playbook renders `searxng/settings.yml.j2` on the server and reads the secret from the `SEARXNG_SECRET_KEY` environment variable by default.

For a new deployment, generate a strong key:

```bash
openssl rand -hex 64
```

For an existing deployment, keep using the current production key so existing sessions and signed values remain valid.

Run the playbook from WSL like this:

```bash
# First-time setup: copy the example inventory and fill in real droplet IPs
cp inventory.ini.example inventory.ini   # inventory.ini is gitignored
# (edit inventory.ini, replacing 203.0.113.x placeholders with real droplet IPs)

read -s SEARXNG_SECRET_KEY
export SEARXNG_SECRET_KEY
ansible-playbook -i inventory.ini deploy-static.yml --private-key ~/.ssh/id_ed25519
unset SEARXNG_SECRET_KEY
```

The `read -s` command keeps the secret out of terminal output. Avoid passing the secret directly on the command line because it can be captured in shell history.

## Files

| Path | Committed? | Purpose |
|---|---|---|
| `searxng/settings.yml.j2` | Yes | Deploy-time Jinja template; rendered to `searxng/settings.yml` on the server |
| `searxng/settings.yml.example` | Yes | Example for reviewers — placeholder secret |
| `searxng/settings.yml` | **No** (gitignored) | Real settings file; should never have a real secret committed |
| `inventory.ini.example` | Yes | Example inventory with RFC 5737 placeholder IPs |
| `inventory.ini` | **No** (gitignored) | Real fleet inventory with production droplet IPs — never commit (`.github/copilot-instructions.md` §3.6) |
| `k8s-external-ingress.yaml.example` | Yes | Example K8s ingress with RFC 5737 placeholder VPC IPs |
| `k8s-external-ingress.yaml` | **No** (gitignored) | Real ingress manifest with VPC private IPs — apply from a local copy then delete |
