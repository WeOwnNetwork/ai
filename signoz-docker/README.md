# signoz-docker — OPTIONAL self-hosted SigNoz copier template

> **MIGRATION PENDING:** this template still uses the heavy-cloud-init pattern.
> The repo-wide canonical pattern is Path C (thin cloud-init + ansible app
> layer) plus Layer 2 (bootstrap-secret rotation). See
> [`docs/INFRA_BOOTSTRAP_PATTERN.md`](../docs/INFRA_BOOTSTRAP_PATTERN.md) for
> the rationale and the per-project migration checklist. Reference
> implementation: [`s004-deployment/`](../s004-deployment/).
>
> ---
>
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
