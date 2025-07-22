# WordPress Cohort/Agency Site

This directory contains Docker configs, plugin setup, and scripts for deploying a modular WordPress stack for WeOwn and cohort participants.

## Stack Includes
- FluentBoards
- FluentCRM
- WP Fusion
- WPCode
- Cadence Theme

## Structure
- `docker/` – Docker Compose, environment, and config templates.
- `scripts/` – Setup and utility scripts.

## Security
- Never commit real secrets or site config.
- Use `.env.example` as a guide. Credentials must be loaded at runtime from secrets storage.