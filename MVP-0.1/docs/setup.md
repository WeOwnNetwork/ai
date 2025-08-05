# MVP-0.1 — Setup Guide

Step-by-step instructions for deploying the WeOwn agentic stack on Kubernetes or locally.

---

## Prerequisites

- DigitalOcean account (or compatible K8s provider)
- Registered domain (e.g., romandid.xyz)
- [kubectl](https://kubernetes.io/docs/tasks/tools/) and [Helm](https://helm.sh/docs/intro/install/) installed locally
- Git, Docker, and Docker Compose installed for local dev (optional)

---

## 1. Kubernetes Cluster Setup

*(If you’re here, your cluster is ready!)*

- 2 nodes, each with 2 vCPUs, 2GB RAM, 60GB storage

---

## 2. Domain Transfer: Porkbun → DigitalOcean DNS

> See detailed, step-by-step transfer instructions below.

---

## 3. Helm Deploy: AnythingLLM + LLM-D

> After DNS is live, you’ll deploy both apps using our pre-built Helm chart.
> See [../helm/README.md](../helm/README.md) for chart usage.

---

## 4. Local Testing (Optional)

You can also run both apps locally with Docker Compose (see `/compose/docker-compose.yaml`).

---

## 5. Next Steps

- See `/docs/usage.md` for advanced config, team sharing, and security controls.

---