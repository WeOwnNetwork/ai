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
read -s SEARXNG_SECRET_KEY
export SEARXNG_SECRET_KEY
ansible-playbook -i inventory.ini deploy-static.yml --private-key ~/.ssh/id_ed25519
unset SEARXNG_SECRET_KEY
```

The `read -s` command keeps the secret out of terminal output. Avoid passing the secret directly on the command line because it can be captured in shell history.

## Files

- `searxng/settings.yml.j2` is the deploy-time template.
- `searxng/settings.yml.example` is only an example for reviewers.
- `searxng/settings.yml` should not be committed with a real secret.
