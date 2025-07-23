#!/bin/bash

echo "Vaultwarden Self-Hosting Quickstart"

# Generate Argon2id hash for admin token (secure, interactive)
echo "Please enter your desired Vaultwarden admin password (will not echo):"
HASH=$(docker run -it --rm vaultwarden/server:latest /vaultwarden hash)
if [ -z "$HASH" ]; then
    echo "Hash generation failed. Please try again."
    exit 1
fi

# Create .env file with secure hash
echo "ADMIN_TOKEN=$HASH" > .env
echo "WEBSOCKET_ENABLED=true" >> .env

echo "Docker .env configured with hashed admin token."
echo "Starting Vaultwarden..."

# Start Vaultwarden with Docker Compose
docker compose up -d

echo "Vaultwarden is running at http://localhost:8080"
echo
echo "IMPORTANT:"
echo "- Your admin password (NOT the hash) is how you access /admin!"
echo "- Save it in a safe place—you cannot recover it if lost."
echo "- Access the admin panel at http://localhost:8080/admin"