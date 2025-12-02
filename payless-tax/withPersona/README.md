# Payless Tax – Persona KYC Demo

Streamlit demo app for Payless Tax, showing a web KYC onboarding journey backed by Persona and MySQL.

- Landing page collects basic lead info (name, email).
- Backend stores leads and KYC state in MySQL.
- Persona hosted flow handles passport + personal details verification.
- Persona API is polled for final status and sanctions/watchlist results.
- Only fully cleared users are marked as **VERIFIED** (allowed to access Connex.ai agents).

This project is designed to run both locally (Docker + uv) and on a DigitalOcean droplet (e.g. `withpersona.payless.tax`).

---

## 1. Project layout

Key files in this folder:

- `app.py` – Streamlit frontend + workflow.
- `db.py` – MySQL connection + schema (`users` table) + helpers.
- `persona_client.py` – Persona API client (inquiries + sanctions/watchlist summary).
- `docker-compose.yml` – Runs MySQL (`db`) and the app (`app`) together.
- `Dockerfile` – Builds the app image for the `app` service.
- `.env.example` – Template for environment variables.
- `deploy/with-persona-docker-compose.service` – Systemd unit for running the stack on a droplet.
- `deploy/setup-withpersona-droplet.sh` – Helper script to set up Docker + Compose + Nginx wiring on a droplet.

---

## 2. Environment variables (.env)

Create a `.env` file in this directory based on `.env.example`:

```bash
cp .env.example .env
```

Then edit `.env` to set your real values:

- **DB settings**
  - `DB_HOST` – usually `localhost` on your laptop; in Docker this is overridden to `db`.
  - `DB_PORT` – `3306`.
  - `DB_USER` – MySQL user created by `docker-compose.yml` (default `payless_user`).
  - `DB_PASSWORD` – MySQL user password (default `payless_password`).
  - `DB_NAME` – database name (default `payless_tax`).

- **Persona settings**
  - `PERSONA_API_KEY` – your Persona **sandbox** API key.
  - `PERSONA_INQUIRY_TEMPLATE_ID` – Inquiry Template ID (starts with `itmpl_...`).

### 2.1 Configuring Persona

1. Log into Persona dashboard in **Sandbox**.
2. Create or select an **Inquiry Template** that includes:
   - Government ID verification (passport).
   - Personal details collection.
   - Watchlist / sanctions / AML checks.
3. Configure workflow rules so that:
   - If watchlist/OFAC hits occur, the inquiry is **auto-declined**.
4. Copy the Inquiry Template ID (e.g. `itmpl_abc123...`) into `PERSONA_INQUIRY_TEMPLATE_ID` in `.env`.

---

## 3. Local development

You can run this project either entirely in Docker (recommended for parity with the droplet) or with uv + a local Docker MySQL.

### 3.1 Run with Docker Compose (app + DB)

From `payless-tax/withPersona`:

```bash
# First time only – create .env
cp .env.example .env
# edit .env to set Persona keys and template id

# Start the stack
docker compose up --build
# or, on systems with docker-compose v5 installed as docker-compose
# docker-compose up -d --build
```

This will:

- Start **MySQL 8.0** as `db` container (`payless_tax_mysql`).
- Build and run the **Streamlit app** as `app` container (`payless_tax_app`).

When it’s up, open:

```text
http://localhost:8501
```

Workflow:

1. Fill in full name + email.
2. Click **Sign up and start KYC**.
3. On Step 2, click **Start KYC with Persona** to open the hosted flow.
4. Complete KYC in Persona’s sandbox.
5. Return to the app and click **Refresh KYC Status**.

The app will display Persona status + decision and any sanctions/watchlist info. Only when Persona has fully approved and no watchlist report is declined will the user be treated as **VERIFIED**.

### 3.2 Run app locally with uv (without Docker for the app)

You can also run the app on your laptop using uv, while MySQL still runs in Docker:

```bash
# Start only the db service
cd payless-tax/withPersona

docker compose up db -d

# In another terminal, create a Python env via uv
uv sync
uv run streamlit run app.py
```

The app will bind to `http://localhost:8501` by default.

Make sure your `.env` has:

```env
DB_HOST=localhost
```

so the local Python process can connect to the MySQL container via the host.

---

## 4. Droplet deployment (withpersona.payless.tax)

A typical flow for deploying to a DigitalOcean droplet:

1. **Copy code to droplet**

   ```bash
   scp -r withPersona root@<DROPLET_IP>:/opt/withPersona
   ```

2. **SSH into droplet**

   ```bash
   ssh root@<DROPLET_IP>
   cd /opt/withPersona
   ```

3. **Create `.env` on droplet**

   ```bash
   cp .env.example .env
   nano .env
   ```

   - Set `PERSONA_API_KEY` and `PERSONA_INQUIRY_TEMPLATE_ID` as per your sandbox.

4. **Install Docker + Compose + Nginx and set up services**

   ```bash
   chmod +x deploy/setup-withpersona-droplet.sh
   APP_DOMAIN=withpersona.payless.tax bash deploy/setup-withpersona-droplet.sh
   ```

   This script will:

   - Install `docker.io`, `docker-compose`, `nginx`, `git`.
   - Create/enable `with-persona-docker-compose.service` to run `docker-compose up -d` from this directory.
   - Install an Nginx site for `withpersona.payless.tax` that proxies to `127.0.0.1:8501` (if you choose to use Nginx rather than Apache).

5. **Start/verify the stack manually if needed**

   ```bash
   docker-compose up -d
   docker-compose ps
   curl -I http://127.0.0.1:8501/
   ```

6. **DNS**

   - Create an A record: `withpersona.payless.tax` → droplet IP.

7. **Optional HTTPS**

   If using Nginx:

   ```bash
   apt-get install -y certbot python3-certbot-nginx
   certbot --nginx -d withpersona.payless.tax
   ```

   If using Apache:

   ```bash
   apt-get install -y certbot python3-certbot-apache
   certbot --apache -d withpersona.payless.tax
   ```

---

## 5. KYC & sanctions behavior

Internally, the app uses `persona_client.summarize_kyc` to:

- Fetch the inquiry with `include=account.reports`.
- Inspect `data.attributes.status` and `data.attributes.decision`.
- Inspect all included `report` objects whose `report-type` contains `watchlist`, `sanctions`, or `aml`.
- Mark the user as **allowed** only if:
  - `decision == "approved"`, and
  - no watchlist/sanctions/AML report has `decision == "declined"`.

The Streamlit UI:

- Shows Persona status + decision.
- Lists any sanctions/watchlist reports when verification fails.
- Only advances to the final dashboard when the user has fully passed these checks.

---

## 6. Troubleshooting

- **Error 404 "Record not found" when creating inquiry**
  - Check that `PERSONA_INQUIRY_TEMPLATE_ID` is set and valid for your **sandbox** project.

- **`address already in use` on port 3306 (droplet)**
  - The droplet already runs MySQL. Remove the `ports: "3306:3306"` line from the `db` service in `docker-compose.yml` on the droplet; the app only needs internal Docker networking.

- **`KeyError: 'ContainerConfig'` from docker-compose 1.29**
  - Replace the Ubuntu docker-compose package with a newer binary (v2+), as described above, or use plain `docker compose` with Docker’s plugin model.

If you run into any other issue, capture the exact error message (and relevant `docker-compose ps` output) and debug from there.
