# We Own AI Architecture Diagrams

This directory contains modular architecture diagrams for the We Own AI platform, showing our self-hosted, single-tenant Kubernetes deployment model across multiple focused views.

## Architecture Files

**High-Level Overview:**
- `weown-ai-architecture.mmd` - End-to-end platform architecture showing tenancy patterns, current apps, and planned integrations

**Per-Application Details:**
- `weown-anythingllm.mmd` - AnythingLLM focus (represents We Own AI Lite SKU)
- `weown-wordpress-fluent.mmd` - WordPress + Fluent Suite capabilities and integrations  
- `weown-n8n.mmd` - n8n workflow automation and orchestration
- `weown-vaultwarden.mmd` - Centralized secrets and credential management
- `weown-agents.mmd` - Agent systems overview (kagent.dev + ElizaOS)

## Status Legend

All diagrams use consistent status indicators:

- **Current** (solid blue) - Production ready, actively deployed
- **In progress** (solid green) - Active development, deployment system complete
- **Planned** (dashed gray) - Roadmap items, future integrations
- **Paused/backlog** (dotted gray, italic) - Resource constraints or deprioritized

## How to View

**GitHub**: Files render automatically with native Mermaid support

**Local Viewing**: Use any Mermaid-compatible viewer:
- [Mermaid Live Editor](https://mermaid.live/) - Copy/paste content
- VS Code with Mermaid Preview extension
- Obsidian, Typora, or other Markdown editors with Mermaid support

## Key Architecture Notes

- **One app per Helm chart** with tenant-specific values for one-click replication
- **Single-tenant isolation** - each brand/cohort/member gets dedicated K8s environment
- **External LLM APIs** - no on-cluster model inference, connects to OpenAI/Anthropic/etc.
- **Minimal workflows exist today** - WordPress/Fluent/n8n workflows co-built with cohorts based on requests
- **We Own AI Lite** = AnythingLLM-only deployment for simplified use cases
- **Enterprise security** - zero-trust networking, Pod Security Standards, TLS 1.3, SOC2/ISO42001 ready
