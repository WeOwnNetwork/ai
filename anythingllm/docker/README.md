# AnythingLLM Deployment: ethdenver-ccc-bot

### Overview
This instance of AnythingLLM is deployed as a Docker container on a DigitalOcean Droplet in the **ATL1** region. 

### Deployment Specifications
- **Image:** `mintplexlabs/anythingllm`
- **Container Name:** `anythingllm_ethdenver`
- **Host Path:** `/root/ethdenver_storage`
- **External Port:** 3001

### Persistence & Data
All application state (Vector DB, Chat Logs, Documents) is stored on the host at:
`/root/ethdenver_storage`

### How to Update/Redeploy
To pull the latest image and restart the container:
```bash
docker stop anythingllm_ethdenver
docker rm anythingllm_ethdenver
docker pull mintplexlabs/anythingllm
docker run -d -p 3001:3001 \
  --name anythingllm_ethdenver \
  -v /root/ethdenver_storage:/app/server/storage \
  -v /root/ethdenver_storage/.env:/app/server/.env \
  --restart always \
  mintplexlabs/anythingllm