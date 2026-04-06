# App

Flutter client for Android, iOS, Windows, macOS, and Linux.

## Purpose

The app talks directly to the local Codex `app-server` over WebSocket JSON-RPC. Direct mode defaults to the local machine endpoint, and public access is expected to be handled through `frp` or another network boundary when needed.

## Current Features

- Switch between live direct mode and local demo mode
- Configure the Codex app-server URL
- Load thread list
- View thread detail and operation timeline
- Open a realtime event stream shell
- Create new threads from the client
- Send follow-up prompts and steer active turns
- Interrupt active turns
- Review and respond to approval, user-input, and MCP requests

## Run

```bash
flutter pub get
flutter run
```

Desktop examples:

```bash
flutter run -d windows
flutter run -d macos
flutter run -d linux
```

## Connect To Local App-Server

Start the local app-server if it is not already running:

```bash
codex app-server --listen ws://127.0.0.1:8766
```

If you want the Flutter app to watch the exact live session that VS Code is
using, point VS Code `chatgpt.cliExecutable` to the proxy in
`../proxy/`, then set the app endpoint to:

```text
ws://127.0.0.1:8767
```

If you want standalone direct mode instead, keep using:

```text
ws://127.0.0.1:8766
```

Then configure the app in `Direct` mode with one of these URLs:

- Windows app: `ws://127.0.0.1:8766`
- macOS app: `ws://127.0.0.1:8766`
- Linux app: `ws://127.0.0.1:8766`
- Android emulator: `ws://10.0.2.2:8766`
- iOS simulator: `ws://127.0.0.1:8766`

## Expected App-Server Methods

- `initialize`
- `config/read`
- `model/list`
- `thread/list`
- `thread/loaded/list`
- `thread/read`
- `thread/start`
- `thread/resume`
- `turn/start`
- `turn/steer`
- `turn/interrupt`

The live stream expects JSON-RPC notifications carrying thread activity and server requests. The client normalizes them into its own realtime event model and prefers `occurredAt` style server timestamps when available.
