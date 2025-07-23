# Vaultwarden (Bitwarden-Compatible) Self-Hosted Password Manager

**WeOwn: Full ownership, zero vendor lock-in. Welcome to decentralized secrets management.**

This directory provides a Docker-based quickstart for deploying your own secure Vaultwarden instance—no central provider, 100% ownership and privacy.

## Why Vaultwarden?

- **Store and share secrets, credentials, and environment variables** for your automations, workflows, and GCP/WordPress/AI infra.
- **Full sovereignty:** Self-host locally, on your own cloud, or as a secure subdomain. Your data, your keys.
- **Bitwarden browser/app compatible:** Sync your secrets across devices using browser/mobile apps, just like Bitwarden.
- **No vendor lock-in:** Never depend on WeOwn or a 3rd-party to hold your secrets.

## Quickstart: Local Self-Hosting (Most Private & Easiest for Beginners)

1. **Clone the Repo and Enter the Directory**
    ```bash
    git clone https://github.com/WeOwnNetwork/ai.git
    cd ai/vaultwarden/docker
    ```

2. **Run the Quickstart Script**
    ```bash
    chmod +x quickstart.sh
    ./quickstart.sh
    ```
    - You’ll be prompted for an admin password (not echoed; keep it secure!).
    - The script will generate a strong hash for your password and write your `.env` file.
    - All vault data is stored in `../data` for persistence.

3. **Access Your Vault**
    - Web Vault: [http://localhost:8080](http://localhost:8080)
    - Admin Panel: [http://localhost:8080/admin](http://localhost:8080/admin)
    - Enter the original admin password you set (not the hash).

4. **Persistence & Backups**
    - Your vault data is always stored in `../data`. Do not delete this folder.
    - Use the built-in admin backup tools to export your vault regularly.

## Using Bitwarden Browser Extensions & Mobile Apps

- Install the [official Bitwarden extension/app](https://bitwarden.com/download/) (Chrome, Firefox, Safari, Edge, iOS, Android).
- Set the server URL to `http://localhost:8080` (local) or your custom domain (see cloud setup below).
- Log in using the Vaultwarden account you create.
- **Sync across devices and use autofill.**

## Cloud Self-Hosting (Recommended for Teams/Orgs or Always-On Access)

**You can deploy Vaultwarden to any cloud or VPS provider using the same Docker setup. Popular options:**
- GCP (Google Cloud Platform)
- AWS (EC2, Lightsail)
- DigitalOcean, Vultr, Hetzner, Linode, Reclaim Cloud, etc.

### Steps:
1. **Provision a VM/Server (e.g., GCP e2-micro, included in the free tier in many regions)**
2. **Install Docker and Docker Compose**
3. **Clone your WeOwn repo and run the `quickstart.sh` script as above**
4. **Open ports 80 (HTTP) and 443 (HTTPS) in your firewall**
5. **Set up a reverse proxy (Caddy, NGINX, or Traefik) to enable HTTPS with a free Let’s Encrypt certificate**
6. **Point your subdomain (e.g., `vault.yoursite.com`) to your server’s IP (set an A record in your domain’s DNS)**
7. **Access your vault securely at `https://vault.yoursite.com`**

#### **Pricing**
- Most VMs (GCP e2-micro) are $0–$5/month for light usage (free if eligible for GCP Free Tier)
- Domain: ~$1/month
- SSL: Free (Let’s Encrypt)
- Backups: $1–$3/month (optional, depends on provider)

## Adding Users, Organizations, and Sharing

- **Single user:** Create your own vault, add secrets.
- **Teams:** Invite users via the admin panel (SMTP config recommended for email invites).
- **Orgs:** Set up organizations for secure team sharing and roles.
- **Backups:** Use the built-in Backup Database tool regularly.

## Security and Best Practices

- **Never share your admin password.** Store it offline or in a secure location.
- **Do not expose Vaultwarden to the public internet without HTTPS and strong firewall rules.**
- **Disable public registration** if you do not want random users signing up.
- **WebSockets enabled by default** for real-time updates/sync.
- **For cloud/remote, always use HTTPS (reverse proxy + Let’s Encrypt).**
- **If using a shared instance, export your vault and migrate to your own system ASAP.**

## Advanced Setup

- **Customize Docker Compose:** Change ports, add volumes, etc.
- **Set up SMTP:** Enable user invites, password resets.
- **Reverse Proxy:** Use Caddy, NGINX, or Traefik for SSL and clean domain access.
- **Migration:** Export your vault and restore on any new instance/server.
- **Persistence:** Always use mounted data volumes for full data safety.

## Help & Troubleshooting

- **Resetting admin password:** Re-run `quickstart.sh` to generate a new hash, update your `.env`, and restart Docker Compose.
- **Vaultwarden Wiki:** See the [official wiki](https://github.com/dani-garcia/vaultwarden/wiki) for all advanced options and troubleshooting.

## Cohort/Team Use & “Should We Host a Shared Instance?”

- **Default:** Every cohort member is encouraged to self-host (locally or in the cloud) for full privacy and control.
- **Option:** We may offer a secure, private WeOwn-hosted Vaultwarden for those who need it short-term or for demo/team use.
    - If you would prefer a shared instance for onboarding, please let us know!
    - *We will always support export/import so you can migrate to your own vault at any time.*

## Automated Setup: Coming Soon

We are building an agent (script/automation) that will:
- Clone this repo for you
- Run all Docker setup
- Walk you through password and .env setup
- Deploy either locally or to your cloud
- Configure your subdomain and HTTPS automatically

**For now:**  
Just follow the quickstart steps above. Full automation is coming!