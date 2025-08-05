# WeOwn AI MVP-0.1

**Private, self-hosted LLM stack for WeOwn cohorts and agency members.**

---

## Overview

This directory contains everything needed to deploy a secure, fully private, and easily replicable agentic AI stack—including AnythingLLM (chat + RAG) and LLM-D (self-hosted model API)—on your own Kubernetes cluster or local machine.

- **Default:** Kubernetes (K8s) deploy with Helm (DigitalOcean or compatible)
- **Optional:** Local self-hosting with Docker Compose for fast prototyping or no-cloud use

## Contents

- `anythingllm/` — AnythingLLM app configs and customizations
- `llm-d/` — LLM-D app configs and model settings
- `helm/` — Helm charts for automated k8s deploys
- `k8s/` — Raw manifests for debugging/learning
- `compose/` — Docker Compose for local dev/test
- `docs/` — All setup, usage, and team onboarding docs
- `.env.example` — Example environment variables for secrets and config
- `README.md` — (this file)
- `CHANGELOG.md` — All updates and improvements

## Quick Start

1. **Deploy on Kubernetes**  
   See [docs/setup.md](./docs/setup.md) for end-to-end cluster setup, domain, and deployment steps.

2. **Local Testing (Optional)**  
   Run `docker-compose up` in `/compose` to bring up both services locally.

## Security & Privacy

- **By default, all deployments are private (no public chat/API exposure).**
- See `/docs/usage.md` for team sharing and advanced options.

## Support

Questions or need help?  
See our internal playbooks, open an issue, or join the #infra-support channel.

---
