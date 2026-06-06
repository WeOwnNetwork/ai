# signoz-docker — OPTIONAL self-hosted SigNoz copier template

## Migration status (bootstrap pattern)

See [`docs/INFRA_BOOTSTRAP_PATTERN.md`](../docs/INFRA_BOOTSTRAP_PATTERN.md) for
the shared pattern + 6-step migration checklist. This project's state today:

| Layer | Status | Notes |
|---|---|---|
| Layer 1 (DO Spaces remote state) | **Done** | [`template/terraform/backend.tf.jinja`](template/terraform/backend.tf.jinja) + [`init.sh.jinja`](template/terraform/init.sh.jinja) (PR #26). |
| Layer 2 (bootstrap-secret rotation) | **Pending** | No `rotate-bootstrap-secret.sh`. Reference: copy from [`anythingllm-docker/sites/s004/terraform/templates/cloud-init.yaml`](../anythingllm-docker/sites/s004/terraform/templates/cloud-init.yaml). |
| Path C (thin cloud-init + ansible) | **Partial** | [`template/ansible/deploy.yml.jinja`](template/ansible/deploy.yml.jinja) already uploads compose + runs `docker compose up`, BUT [`template/terraform/templates/cloud-init.yaml.jinja`](template/terraform/templates/cloud-init.yaml.jinja) ALSO embeds the app layer (compose.yaml, Caddyfile, embedded backup.sh, daily cron). Both run, leading to drift. **Slim the cloud-init.** |
| Infisical CLI install | **Legacy** — `install-cli.sh` (capped at v0.38). Switch to artifacts-cli apt repo. Reference: `anythingllm-docker/sites/s004` cloud-init's `install-infisical.sh`. |

Open project-specific items (separate from the bootstrap-pattern migration):

- ZooKeeper `ALLOW_ANONYMOUS_LOGIN: "yes"` documented as accepted risk in
  [`template/docker/compose.prod.yaml.jinja`](template/docker/compose.prod.yaml.jinja)
  and the embedded cloud-init copy. To remove the risk, enable SASL on
  ZooKeeper and add the matching credential to ClickHouse's zookeeper config.

> **STATUS — OPTIONAL / NOT THE PRIMARY PATH**
>
> WeOwn AI observability now uses **SigNoz Cloud** (Yonks' managed account),
> not a self-hosted SigNoz droplet. The primary path is:
>
> 1. [`otel-agent/`](../otel-agent/) — OpenTelemetry Collector deployed on
>    every WeOwn droplet, shipping telemetry to SigNoz Cloud over OTLP gRPC
>    with `OTEL_URL` + `OTEL_KEY` from the Infisical `otel` project.
> 2. `scripts/bootstrap-otel-agent.sh` (one-time per droplet) then
>    `scripts/deploy-otel-fleet.sh` to roll out.
>
> **This `signoz-docker/` copier template is preserved as a future fallback**
> in case we ever need to self-host SigNoz (e.g. data-residency requirement,
> SaaS cost change, vendor lock-in concern). It is NOT deployed today.
> Do NOT `copier copy` this template unless we make an explicit decision to
> migrate off SigNoz Cloud.

---

## What this template would build (if/when we ever need it)

A complete self-hosted SigNoz stack on a single DigitalOcean droplet:

- ZooKeeper + ClickHouse (telemetry storage)
- SigNoz schema migrator + SigNoz UI/query service
- SigNoz OTel Collector gateway (receives OTLP from fleet, writes to ClickHouse)
- Caddy reverse proxy with automatic TLS
- All secrets via Infisical runtime injection (no `.env` files)
- Skinny volume-based backups with optional DO Spaces offload
- OpenTofu IaC: droplet + reserved IP + firewall + monitoring alerts
- Ansible deployment playbook

Files: see `copier.yaml` and `template/` for the full structure (19 files).

---

## If we ever need to activate this

1. Get team consensus and an ADR documenting the move off SigNoz Cloud.
2. Create the Infisical project and secrets listed in
   [`template/README.md.jinja`](template/README.md.jinja) "Infisical Secrets
   Required" section.
3. `copier copy signoz-docker/ ../signoz-observability --data-file answers.yaml`
4. Provision: `cd ../signoz-observability/terraform && tofu init && tofu apply`
5. Update `otel-agent/` `OTEL_URL` in Infisical to point at the new private
   gateway IP (`<reserved-ip>:4317`) and bounce the fleet.

Until that day comes, **leave this directory untouched**.

### Infisical Outage Procedures

If Infisical Cloud becomes unavailable, deployments and backups will fail. See [INFISICAL_OUTAGE_RUNBOOK.md](../docs/INFISICAL_OUTAGE_RUNBOOK.md) for emergency procedures including:

- Manual deployment without Infisical
- Local-only backup creation
- Emergency restore procedures
- Recovery steps when Infisical comes back online
