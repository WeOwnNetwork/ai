# n8n Automations & Agents

This directory contains n8n workflow JSON exports, Docker setup, and supporting scripts for WeOwn cohort automation and replication.

## Structure
- `workflows/` – Exported n8n workflow templates (never include credentials).
- `docker/` – Docker Compose, config, and environment templates.
- `scripts/` – Optional helper scripts for deployment or maintenance.

## Security
- **Never commit real credentials, API keys, or secrets.**
- Always use `.env.example` for reference.
- Actual secrets must be managed via Vaultwarden or Google Secret Manager.