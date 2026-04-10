FROM golang:1.22-alpine AS builder

WORKDIR /build
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -o orbital-agent .

FROM alpine:latest

RUN apk --no-cache add ca-certificates

WORKDIR /app
COPY --from=builder /build/orbital-agent .

# Config via environment variables
ENV SERVER_ID=""
ENV SERVER_NAME=""
ENV RELAY_URL=""
ENV POLL_INTERVAL_SECONDS="30"
ENV COOLDOWN_MINUTES="5"
ENV CPU_THRESHOLD="90"
ENV RAM_THRESHOLD="90"
ENV DISK_THRESHOLD="85"

# Entrypoint script generates config.json from env vars then runs the agent
COPY docker-entrypoint.sh .
RUN chmod +x docker-entrypoint.sh

ENTRYPOINT ["./docker-entrypoint.sh"]