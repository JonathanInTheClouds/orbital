#!/bin/sh
set -e

# ── Validate required vars ────────────────────────────────────────────────────

if [ "$MULTI_TENANT" != "true" ] && [ -z "$AUTH_TOKEN" ]; then
  echo "ERROR: AUTH_TOKEN is required (or set MULTI_TENANT=true for centralized mode)"
  exit 1
fi

if [ "$FCM_STUB" != "true" ] && [ -z "$FCM_PROJECT_ID" ]; then
  echo "ERROR: FCM_PROJECT_ID is required when FCM_STUB=false"
  exit 1
fi

# ── Resolve FCM service account file ─────────────────────────────────────────
# Supports two approaches:
#   1. FCM_SERVICE_ACCOUNT_FILE — path to a file (e.g. mounted volume/secret)
#   2. FCM_SERVICE_ACCOUNT_B64  — base64-encoded JSON (good for cloud/env-only deploys)

FCM_SA_PATH="$FCM_SERVICE_ACCOUNT_FILE"

if [ -z "$FCM_SA_PATH" ] && [ -n "$FCM_SERVICE_ACCOUNT_B64" ]; then
  FCM_SA_PATH="/run/fcm-service-account.json"
  echo "$FCM_SERVICE_ACCOUNT_B64" | base64 -d > "$FCM_SA_PATH"
  echo "relay: FCM service account decoded from environment"
fi

if [ "$FCM_STUB" != "true" ] && [ -z "$FCM_SA_PATH" ]; then
  echo "ERROR: FCM_SERVICE_ACCOUNT_FILE or FCM_SERVICE_ACCOUNT_B64 required when FCM_STUB=false"
  exit 1
fi

# ── Ensure data directory exists ──────────────────────────────────────────────

STORE="${STORE_FILE:-/data/devices.json}"
mkdir -p "$(dirname "$STORE")"

# ── Write config.json ─────────────────────────────────────────────────────────

cat > /app/config.json << EOF
{
  "listen_addr": "${LISTEN_ADDR:-:8080}",
  "auth_token": "${AUTH_TOKEN}",
  "store_file": "${STORE}",
  "multi_tenant": ${MULTI_TENANT:-false},
  "apns": {
    "stub": true
  },
  "fcm": {
    "stub": ${FCM_STUB:-false},
    "service_account_file": "${FCM_SA_PATH}",
    "project_id": "${FCM_PROJECT_ID}"
  }
}
EOF

echo "orbital-relay starting (multi_tenant=${MULTI_TENANT:-false}, listen=${LISTEN_ADDR:-:8080})"
exec ./orbital-relay -config /app/config.json
