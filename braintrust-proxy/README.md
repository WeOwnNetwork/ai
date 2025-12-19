# Braintrust Proxy for AnythingLLM + OpenRouter

[![WeOwn AI Stack](https://img.shields.io/badge/WeOwn-AI%20Stack-blue)](https://weown.xyz)
[![Braintrust](https://img.shields.io/badge/Braintrust-Observability-green)](https://braintrust.dev)
[![Python](https://img.shields.io/badge/Python-3.12-blue)](https://python.org)

A lightweight Python proxy that adds **Braintrust LLM observability** to AnythingLLM when using OpenRouter.

## Why This Exists

AnythingLLM isolates chat history per-user by design. This proxy captures **ALL LLM calls from ALL users** at the API layer, giving you complete observability in Braintrust.

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                   AnythingLLM                       │
│        Generic OpenAI Provider                      │
│   Base URL: http://braintrust-proxy:8080/v1         │
└───────────────────────┬─────────────────────────────┘
                        │
┌───────────────────────▼─────────────────────────────┐
│           Braintrust Proxy (Python/Flask)           │
│   ✅ Logs all prompts, responses, tokens            │
│   ✅ Captures latency metrics                       │
│   ✅ Tracks model usage across ALL users            │
│   ✅ Sends traces to Braintrust                     │
└───────────────────────┬─────────────────────────────┘
                        │
┌───────────────────────▼─────────────────────────────┐
│                   OpenRouter                        │
│   Single API key → 100+ models                      │
└─────────────────────────────────────────────────────┘
```

## Quick Start

### Deploy to Kubernetes

```bash
cd braintrust-proxy
./deploy.sh   # Prompts for API keys, deploys with kubectl
```

### Configure AnythingLLM

| Setting | Value |
|---------|-------|
| Provider | Generic OpenAI |
| Base URL | `http://braintrust-proxy.braintrust.svc.cluster.local:8080/v1` |
| API Key | `any-value` (proxy handles auth) |
| Model | Any OpenRouter model (e.g., `anthropic/claude-4.5-sonnet`) |

## Local Development

```bash
# Install dependencies
pip install -r requirements.txt

# Set environment variables
export BRAINTRUST_API_KEY="your-key"
export OPENROUTER_API_KEY="sk-or-..."
export BRAINTRUST_PROJECT_NAME="AnythingLLM"

# Run
python app.py
```

## Container Registry Setup

The deploy script walks you through this, but here are manual instructions:

### Option 1: DigitalOcean Container Registry (DOCR)

**Recommended if using DigitalOcean Kubernetes.**

```bash
# 1. Create registry in DO Console (or via doctl)
# https://cloud.digitalocean.com/registry

# 2. Start Docker Desktop
open /Applications/Docker.app

# 3. Login to DOCR
doctl registry login

# 4. Build and push
docker build -t registry.digitalocean.com/YOUR-REGISTRY/braintrust-proxy:latest .
docker push registry.digitalocean.com/YOUR-REGISTRY/braintrust-proxy:latest

# 5. Integrate cluster with registry
# DO Console → Container Registry → Settings → Kubernetes Integration
# Select your cluster and click "Save"
```

### Option 2: GitHub Container Registry (GHCR)

```bash
# 1. Create a Personal Access Token with `write:packages` scope
# https://github.com/settings/tokens

# 2. Start Docker Desktop
open /Applications/Docker.app

# 3. Login to GHCR
echo YOUR_TOKEN | docker login ghcr.io -u YOUR_USERNAME --password-stdin

# 4. Build and push
docker build -t ghcr.io/YOUR_USERNAME/braintrust-proxy:latest .
docker push ghcr.io/YOUR_USERNAME/braintrust-proxy:latest

# 5. Create image pull secret in K8s (deploy.sh does this automatically)
kubectl create secret docker-registry ghcr-secret \
  --docker-server=ghcr.io \
  --docker-username=YOUR_USERNAME \
  --docker-password=YOUR_TOKEN \
  -n braintrust
```

### Troubleshooting

**`docker: command not found`**
```bash
# Fix symlink to Docker CLI
sudo ln -sf /Applications/Docker.app/Contents/Resources/bin/docker /usr/local/bin/docker
```

**`docker-credential-desktop: executable file not found`**
```bash
# Fix credential helper symlinks
sudo ln -sf /Applications/Docker.app/Contents/Resources/bin/docker-credential-desktop /usr/local/bin/docker-credential-desktop
sudo ln -sf /Applications/Docker.app/Contents/Resources/bin/docker-credential-osxkeychain /usr/local/bin/docker-credential-osxkeychain
```

**`Dockerfile cannot be empty`**
- The IDE may show content but the file is empty on disk
- Save the file explicitly or recreate it

**`no match for platform in manifest`**
- Image built for wrong architecture (arm64 vs amd64)
- The deploy script now builds for `linux/amd64` automatically
- Manual fix: `docker buildx build --platform linux/amd64 -t IMAGE --push .`

**`ImagePullBackOff` in Kubernetes**
- Image doesn't exist in registry - build and push first
- Cluster not integrated with DOCR - check DO Console → Container Registry → Settings
- For GHCR: image pull secret not created

**`Secrets already exist` prompt**
- Normal if you ran deploy.sh before - answer N to keep existing secrets, Y to update

**Pod not starting**
```bash
# Check pod status
kubectl get pods -n braintrust
kubectl describe pod -n braintrust -l app=braintrust-proxy
kubectl logs -n braintrust -l app=braintrust-proxy
```

## Docker or Helm

**Docker** packages your app + dependencies into a portable **image**.
**Helm** is a K8s package manager for complex apps.

| Tool | Use When |
|------|----------|
| **Docker + kubectl** | Simple app ✅ (this proxy) |
| **Helm** | Complex app, many configurable resources |

**This proxy uses Docker + kubectl** - no Helm needed.

## Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `BRAINTRUST_API_KEY` | ✅ | Your Braintrust API key |
| `OPENROUTER_API_KEY` | ✅ | Your OpenRouter API key |
| `BRAINTRUST_PROJECT_NAME` | ❌ | Project name (default: "AnythingLLM") |
| `PORT` | ❌ | Server port (default: 8080) |

## What Gets Logged

| Data | Captured |
|------|----------|
| User prompts | ✅ |
| LLM responses | ✅ |
| Token usage | ✅ |
| Latency (ms) | ✅ |
| Model used | ✅ |
| Temperature & params | ✅ |
| Embeddings | ✅ |

## Files

```
braintrust-proxy/
├── app.py              # Flask proxy with Braintrust tracing
├── requirements.txt    # Python dependencies
├── Dockerfile          # Container build recipe
├── deploy.sh           # K8s deployment script
├── MODEL_GUIDE.md      # Model configuration reference
└── README.md
```

## Model Configuration

See **[MODEL_GUIDE.md](MODEL_GUIDE.md)** for:
- Frontier model IDs (Claude 4.5, GPT-5, Gemini 3, etc.)
- How to find model IDs on OpenRouter
- Context window and max token recommendations
- Model recommendations by task

## Security

- ✅ Non-root container
- ✅ No credentials logged
- ✅ Secrets injected during CLI deployment via Kubernetes Secrets (not in code)

## License

MIT - WeOwn.Dev
