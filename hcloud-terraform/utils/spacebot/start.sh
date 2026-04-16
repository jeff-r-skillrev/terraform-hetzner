#!/usr/bin/env bash
# Start spacebot with Docker Compose
# Writes .env pointing SPACEBOT_DATA at the persistent Hetzner volume,
# installs Docker if needed, and brings the service up.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPACEBOT_DATA="/mnt/persist/spacebot/data"

log() { echo ">>> $1"; }

# Install Docker if not present
if ! command -v docker &>/dev/null; then
  log "Installing Docker"
  curl -fsSL https://get.docker.com | sh
fi

# Ensure the data directory exists on the persistent volume
mkdir -p "$SPACEBOT_DATA"

# Write .env alongside docker-compose.yml
log "Writing $SCRIPT_DIR/.env (SPACEBOT_DATA=$SPACEBOT_DATA)"
cat > "$SCRIPT_DIR/.env" << EOF
SPACEBOT_DATA=$SPACEBOT_DATA
EOF

# Start the service
log "Starting spacebot"
cd "$SCRIPT_DIR"
docker compose build --pull
docker compose up -d

log "Spacebot running — data persisted at $SPACEBOT_DATA"
docker compose ps
