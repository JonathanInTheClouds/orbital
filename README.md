# Orbital

Orbital is a Flutter mobile app for monitoring Linux servers over SSH. It gives you a live server dashboard, an in-app terminal, Docker visibility, and a push-alert pipeline backed by a lightweight Go relay and optional per-server agent.

## Current Feature Set

- Add and manage servers with password auth or private keys imported from Files/iCloud Drive, clipboard, or on-device generation
- Store server credentials securely with `flutter_secure_storage`
- View live CPU, RAM, disk, and network metrics from each server
- Track short-term metric history with charts on the server detail screen
- Search, sort, and filter servers by name and connection state
- Open an interactive SSH terminal with session logging
- Inspect Docker containers and images on connected hosts
- Start, stop, restart, and remove containers from the app
- Receive in-app and push alerts for CPU, RAM, and disk threshold breaches
- Configure monitoring intervals, connection timeout, relay settings, and theme mode
- Install and manage the `orbital-agent` from inside the app

## Repository Layout

```text
lib/        Flutter application
agent/      Go alert agent that runs on monitored servers
relay/      Go push-notification relay
docker/     Local SSH test server for development
```

## Architecture

Orbital has three main parts:

1. The Flutter app connects to servers over SSH, displays metrics, opens terminal sessions, and manages local alert history.
2. `orbital-agent` runs on monitored servers and posts threshold breaches to the relay.
3. `orbital-relay` receives device registrations and alerts, then dispatches push notifications through APNs and FCM.

The app can still monitor servers directly over SSH without the agent. The agent is used for background alerting when you want notifications delivered through the relay.

## Flutter App

The app currently includes:

- Servers tab with search, online/offline filtering, and custom server colors
- Server detail screen with gauges, history charts, system info, and memory breakdown
- Terminal screen powered by `dartssh2` and `xterm`
- Docker screen with container state, stats, image listing, and log access
- Alerts screen with unread tracking, mark-as-read, and clear-all actions
- Settings for polling, thresholds, relay registration, developer tools, logs, and theme mode

### Local Storage

- Server metadata is stored in Drift/SQLite
- Secrets are stored in secure device storage
- App settings are stored in `SharedPreferences`
- Terminal sessions can be recorded locally

## Push Notification Flow

Orbital uses Firebase Cloud Messaging in the app and a Go relay for delivery.

High-level flow:

1. The app initializes Firebase and requests notification permissions.
2. The app registers its FCM/APNs device token with the relay for all saved server IDs.
3. `orbital-agent` posts alerts to `POST /alert`.
4. The relay dispatches the notification to registered devices.
5. The app records received alerts in the Alerts screen.

## Relay Service

The relay exposes:

- `POST /register`
- `POST /alert`
- `GET /health`

All write endpoints require:

```text
Authorization: Bearer <auth_token>
```

### Relay Config

The relay loads JSON config with this shape:

```json
{
  "listen_addr": ":8080",
  "auth_token": "replace-me",
  "store_file": "./devices.json",
  "apns": {
    "stub": true,
    "key_file": "",
    "key_id": "",
    "team_id": "",
    "bundle_id": "",
    "sandbox": true
  },
  "fcm": {
    "stub": true,
    "service_account_file": "",
    "project_id": ""
  }
}
```

When `stub` is `false`, the corresponding APNs or FCM credentials are required.

### Run the Relay

```bash
cd relay
go run . -config /path/to/config.json
```

## Agent Service

`orbital-agent` is a small Linux process that reads host metrics and reports threshold breaches to the relay.

It currently supports:

- CPU, RAM, and disk thresholds
- Poll interval and cooldown configuration
- Binary install or container install
- In-app installation flow from the server detail screen

### Agent Config

```json
{
  "server_id": "server-123",
  "relay_url": "https://relay.example.com/alert",
  "auth_token": "replace-me",
  "poll_interval_seconds": 30,
  "cooldown_minutes": 5,
  "thresholds": {
    "cpu_percent": 90,
    "ram_percent": 90,
    "disk_percent": 85
  }
}
```

### Run the Agent

```bash
cd agent
go run . -config /path/to/config.json
```

### Container Build

The agent also ships with a Dockerfile and entrypoint that generate `config.json` from environment variables:

```bash
cd agent
docker build -t orbital-agent .
```

Required environment variables:

- `SERVER_ID`
- `RELAY_URL`
- `AUTH_TOKEN`

Optional environment variables:

- `POLL_INTERVAL_SECONDS`
- `COOLDOWN_MINUTES`
- `CPU_THRESHOLD`
- `RAM_THRESHOLD`
- `DISK_THRESHOLD`

## App Setup

### Prerequisites

- Flutter SDK compatible with Dart `^3.11.3`
- Xcode for iOS builds
- Android Studio / Android SDK for Android builds
- Firebase project configured for the mobile app

### Install Dependencies

```bash
flutter pub get
```

### Run the App

```bash
flutter run
```

### Firebase

This repo already includes Firebase wiring through:

- `lib/firebase_options.dart`
- `android/app/google-services.json`
- `ios/Runner/GoogleService-Info.plist`

If you change Firebase projects, regenerate the FlutterFire config and replace the platform-specific config files.

## Local Development

The repo includes a lightweight SSH test server for app development.

Start it with:

```bash
cd docker
docker compose up --build
```

Then add this host in Orbital:

- Host: `localhost`
- Port: `2222`
- Username: `orbital`
- Password: `orbital`

## Tech Stack

- Flutter
- Riverpod
- Go Router
- Drift + SQLite
- `dartssh2`
- `xterm`
- Firebase Core + Firebase Messaging
- Flutter Local Notifications
- Go for relay and agent services

## Status

This README reflects the current codebase structure and shipped feature set in this repository, replacing the default Flutter starter content that was previously here.
