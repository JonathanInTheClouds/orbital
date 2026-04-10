#!/bin/sh
set -e

# Validate required env vars
if [ -z "$SERVER_ID" ]; then
  echo "ERROR: SERVER_ID environment variable is required"
  exit 1
fi

# If no explicit server name is provided, use the host hostname.
if [ -z "$SERVER_NAME" ]; then
  SERVER_NAME="$(hostname 2>/dev/null || true)"
fi

if [ -z "$RELAY_URL" ]; then
  echo "ERROR: RELAY_URL environment variable is required"
  exit 1
fi

if [ -z "$AUTH_TOKEN" ]; then
  echo "ERROR: AUTH_TOKEN environment variable is required"
  exit 1
fi

# Generate config.json from environment variables
cat > /app/config.json << EOF
{
  "server_id": "${SERVER_ID}",
  "server_name": "${SERVER_NAME}",
  "relay_url": "${RELAY_URL}",
  "auth_token": "${AUTH_TOKEN}",
  "poll_interval_seconds": ${POLL_INTERVAL_SECONDS},
  "cooldown_minutes": ${COOLDOWN_MINUTES},
  "thresholds": {
    "cpu_percent": ${CPU_THRESHOLD},
    "ram_percent": ${RAM_THRESHOLD},
    "disk_percent": ${DISK_THRESHOLD}
  }
}
EOF

echo "orbital-agent starting with server_id=${SERVER_ID} server_name=${SERVER_NAME}"
exec ./orbital-agent -config /app/config.json
