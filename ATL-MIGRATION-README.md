# ATL1 Migration Runbook

**Document:** DigitalOcean workflow for migrating workloads from SFO2 to ATL1  
**Last updated:** 2026-02

---

## Overview

This runbook describes the manual steps to migrate a Droplet (or image) from DigitalOcean’s **SFO2** region to **ATL1**, attach a reserved IP, bind SSL with Certbot, and apply UFW firewall rules. Use it for planned migrations or disaster recovery.

---

## Prerequisites

| Requirement | Notes |
|-------------|--------|
| DigitalOcean account | API token or console access |
| `doctl` (optional) | For API-driven steps; console is sufficient |
| Source Droplet in SFO2 | Powered on and in a consistent state |
| Target region | ATL1 (Atlanta) selected for destination |

---

## 1. SFO2 Droplet Snapshotting

Create a consistent snapshot of the source Droplet in SFO2 before any transfer.

### 1.1 Via Control Panel

1. Log in to [Cloud Control Panel](https://cloud.digitalocean.com/droplets).
2. Select the **SFO2 Droplet** to migrate.
3. **Power Off** the Droplet (optional but recommended for consistency).
4. Open **Images** in the left sidebar (or **Droplet** → **Snapshots**).
5. Click **Take Snapshot**.
6. Name the snapshot (e.g. `sfo2-migration-YYYYMMDD`).
7. Wait for the snapshot to complete (status: **Available**).

### 1.2 Via API (doctl)

```bash
# List Droplets to get the source Droplet ID
doctl compute droplet list --region sfo2

# Power off (optional)
doctl compute droplet-action power-off <DROPLET_ID>

# Create snapshot
doctl compute droplet-action snapshot <DROPLET_ID> --snapshot-name sfo2-migration-$(date +%Y%m%d)
```

### Verification

- In **Images** → **Snapshots**, confirm the new snapshot exists and is **Available**.
- Note the **Image ID** or **Slug** for the transfer step.

---

## 2. Regional Image Transfer to ATL1

Transfer the snapshot from SFO2 to ATL1 so it can be used to create a Droplet in the target region.

### 2.1 Via Control Panel

1. Go to **Images** → **Snapshots** (or **Custom Images**).
2. Open the **⋮** menu for the snapshot created in Step 1.
3. Select **Transfer to Region** (or equivalent).
4. Choose **ATL1 (Atlanta)** as the destination region.
5. Start the transfer and wait until status is **Available** in ATL1.

### 2.2 Via API

```bash
# List images to get snapshot ID
doctl compute image list --type snapshot

# Transfer image to ATL1
doctl compute image transfer <IMAGE_ID> --region atl1
```

### Verification

- In **Images**, filter by region **ATL1** and confirm the transferred image/snapshot is **Available**.

---

## 3. Reserved IP Allocation (134.199.134.120)

Reserve a static IP in ATL1 and (after Droplet creation) assign it to the new Droplet.

### 3.1 Create Reserved IP in ATL1

**Control Panel:**

1. Go to **Networking** → **Reserved IPs**.
2. Click **Reserve IP Address**.
3. Select **Region:** ATL1.
4. Optionally attach to an existing Droplet, or leave unassigned for post-creation attach.
5. Complete; note the reserved IP (e.g. `134.199.134.120`).

**API:**

```bash
# Create reserved IP in ATL1 (no Droplet yet)
doctl compute reserved-ip create --region atl1

# Or create and assign to a Droplet
doctl compute reserved-ip create --region atl1 --droplet-id <DROPLET_ID>
```

### 3.2 Create Droplet from Transferred Image

1. **Create** → **Droplets**.
2. Choose the **transferred image** (ATL1) as the image source.
3. Select plan, size, and **Region: ATL1**.
4. Add SSH key and hostname; create the Droplet.
5. In **Networking** → **Reserved IPs**, **Assign** the reserved IP `134.199.134.120` to this new Droplet.

### Verification

- Droplet is **Running** in ATL1.
- Reserved IP `134.199.134.120` is **Assigned** to that Droplet.
- DNS (if used) is updated to point to `134.199.134.120`.

---

## 4. Post-Migration SSL Binding via Certbot

Bind SSL to the reserved IP hostname using Certbot on the migrated Droplet.

### 4.1 SSH and Prerequisites

```bash
ssh root@134.199.134.120
```

Ensure:

- A/AAAA records for the FQDN point to `134.199.134.120`.
- Ports **80** and **443** are open (see Section 5).

### 4.2 Install Certbot (Ubuntu/Debian)

```bash
apt update && apt install -y certbot
# If using Nginx/Apache plugin:
# apt install -y certbot python3-certbot-nginx   # or python3-certbot-apache
```

### 4.3 Obtain Certificate (Standalone)

```bash
# Stop web server if it binds 80/443
systemctl stop nginx   # or apache2

# Obtain certificate (replace with your FQDN)
certbot certonly --standalone -d example.com -d www.example.com --non-interactive --agree-tos -m admin@example.com

# Restart web server
systemctl start nginx  # or apache2
```

### 4.4 Web Server Plugin (Alternative)

```bash
certbot --nginx -d example.com -d www.example.com --non-interactive --agree-tos -m admin@example.com
# or
certbot --apache -d example.com -d www.example.com --non-interactive --agree-tos -m admin@example.com
```

### 4.5 Auto-Renewal

```bash
# Test renewal
certbot renew --dry-run

# Certbot installs a systemd timer; ensure it is enabled
systemctl enable certbot.timer && systemctl start certbot.timer
```

### Verification

- `https://<your-fqdn>` loads with valid TLS.
- `certbot certificates` lists the certificate and expiry.

---

## 5. UFW Firewall Rules

Apply a minimal UFW profile: SSH, HTTP, HTTPS.

### 5.1 Defaults and SSH

```bash
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp comment 'SSH'
```

### 5.2 Web and Enable

```bash
ufw allow 80/tcp comment 'HTTP'
ufw allow 443/tcp comment 'HTTPS'
ufw enable
```

### 5.3 Verify

```bash
ufw status numbered
```

Expected (order may vary):

```
22/tcp   ALLOW IN    Anywhere   # SSH
80/tcp   ALLOW IN    Anywhere   # HTTP
443/tcp  ALLOW IN    Anywhere   # HTTPS
```

### Verification

- SSH: `ssh root@134.199.134.120` (port 22).
- HTTP: `curl -I http://134.199.134.120` (port 80).
- HTTPS: `curl -I https://<your-fqdn>` (port 443).

---

## Summary Checklist

| Step | Action | Verification |
|------|--------|--------------|
| 1 | Snapshot Droplet in SFO2 | Snapshot **Available** in Images |
| 2 | Transfer image to ATL1 | Image **Available** in ATL1 |
| 3 | Allocate reserved IP in ATL1; create Droplet from image; assign IP | Droplet running; IP `134.199.134.120` assigned |
| 4 | Certbot SSL for FQDN | Valid HTTPS and renewal test OK |
| 5 | UFW: 22, 80, 443 | `ufw status` and connectivity tests |

---

## Rollback / Notes

- **Snapshot:** Keep the SFO2 snapshot until ATL1 is verified; then delete per retention policy.
- **Reserved IP:** If you destroy the Droplet, release or reassign the reserved IP to avoid floating charges.
- **DNS:** Point domains to `134.199.134.120` only after SSL and services are verified on the new Droplet.

---

*Runbook maintained for ATL1 migration and DR procedures.*
