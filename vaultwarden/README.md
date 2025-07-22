# Vaultwarden (Bitwarden-Compatible) Self-Hosted Password Manager

This directory provides Docker setup and guides for deploying Vaultwarden for secure secrets management.

## Purpose
- Store and share secrets, credentials, and environment variables for WeOwn automation and infra.
- Can be used by individual cohort members, or as a shared instance for the team.

## Structure
- `docker/` – Docker Compose, persistent volumes, and config.
- `README.md` – Setup and best practices.

## Security
- Never commit the real Vaultwarden DB or config files.
- Use your own `.env` and secure storage for the master password.

## Usage
- Each user/team can self-host, or connect to the shared WeOwn Vaultwarden (if provided).