FROM golang:1.25-alpine AS builder

WORKDIR /build
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -o orbital-relay .

FROM alpine:latest

RUN apk --no-cache add ca-certificates

WORKDIR /app
COPY --from=builder /build/orbital-relay .
COPY docker-entrypoint.sh .
RUN chmod +x docker-entrypoint.sh

# ── Single-tenant mode ────────────────────────────────────────────────────────
# AUTH_TOKEN   Required. Bearer token agents must present.
#
# ── Multi-tenant (centralized relay) mode ────────────────────────────────────
# MULTI_TENANT=true  Accept any bearer token; each token is its own namespace.
#              AUTH_TOKEN is ignored. Tokens must be ≥32 chars.
#
# ── FCM (required unless FCM_STUB=true) ──────────────────────────────────────
# FCM_PROJECT_ID              Firebase project ID.
# FCM_SERVICE_ACCOUNT_FILE    Path to service-account JSON (use a volume mount).
# FCM_SERVICE_ACCOUNT_B64     Base64-encoded service-account JSON (alternative).
#
# ── General ───────────────────────────────────────────────────────────────────
# LISTEN_ADDR   Default: :8080
# STORE_FILE    Default: /data/devices.json  (mount a volume at /data)
# FCM_STUB      Set true to log instead of sending real pushes.

ENV AUTH_TOKEN="dev-token"
ENV MULTI_TENANT="false"
ENV LISTEN_ADDR=":8080"
ENV STORE_FILE="/data/devices.json"
ENV FCM_STUB="true"
ENV FCM_PROJECT_ID=""
ENV FCM_SERVICE_ACCOUNT_FILE=""
ENV FCM_SERVICE_ACCOUNT_B64=""

EXPOSE 8080
VOLUME ["/data"]

ENTRYPOINT ["./docker-entrypoint.sh"]
