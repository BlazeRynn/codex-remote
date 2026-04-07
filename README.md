# Codex Remote

Desktop and mobile companion for viewing and operating local Codex threads.

This repo currently contains:

- `app/`: the Flutter client for Android, iOS, Windows, macOS, and Linux
- `proxy/`: a local stdio tee proxy that mirrors VS Code's Codex session to WebSocket on Windows, macOS, and Linux

The Flutter app connects directly to the local Codex `app-server` over WebSocket. If you need remote exposure, keep that outside this repo behind your own network boundary such as `frp`.

## Goals

- View thread lists from the local Codex app-server
- Read thread content, turns, and operation items
- Watch live updates over a realtime channel
- Create and continue turns from the client
- Handle approvals and follow-up actions remotely

## Non-Goals For The First Milestone

- No relay server
- No cloud persistence of session history
- No remote execution by default
- No direct public exposure of local Codex internals

## Current Architecture

```text
Android / iOS / Windows / macOS / Linux Flutter App
        |
    WebSocket JSON-RPC
        |
   codex app-server
        |
   Local Codex threads
```

The app talks directly to the local `app-server`. If you expose it remotely, do that through your own network boundary such as `frp`.

## Share One App-Server With VS Code

The VS Code Codex extension normally launches its own private `stdio` app-server
instance. To let Flutter observe the same live session without breaking VS
behavior, use the local proxy in `proxy/`.

Launchers by platform:

- Windows source launcher: `proxy/codex-proxy.cmd`
- macOS / Linux source launcher: `proxy/codex-proxy`
- Optional Windows local build output: `proxy/build/codex-proxy.exe`
- Optional macOS / Linux local build output: `proxy/build/codex-proxy`

Point VS Code setting `chatgpt.cliExecutable` to one of those paths. The proxy
keeps VS Code on a normal private `stdio` child app-server, and mirrors that
same session to `ws://127.0.0.1:8767` for secondary clients such as Flutter.

On macOS and Linux, make the source launcher executable before using it:

```bash
chmod +x proxy/codex-proxy
```

## MVP Scope

### Included

- App-server URL configuration
- Selectable `direct` and `demo` data sources
- Thread list screen
- Thread detail screen
- Basic operation timeline rendering
- Realtime connection shell
- Model selection and runtime state
- Composer, interrupt, and approval response flows
- Shared codebase for Android, iOS, Windows, macOS, and Linux

### Deferred

- Push notifications
- Rich offline cache
- Multi-device account management

## Repository Layout

```text
README.md          Project overview and setup notes
app/               Flutter application
proxy/             VS Code stdio tee proxy with websocket mirror
```

## App Stack

- Flutter
- Dart
- Material 3 UI
- `dart:io` WebSocket for app-server JSON-RPC

Additional packages can be added once the core flows are in place.

## App-Server Surface

The app talks directly to Codex `app-server` JSON-RPC methods such as:

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

Realtime updates are consumed from the same WebSocket connection. The client normalizes notifications into its own event model and prefers server-side timestamps when available.

## Local Development

1. Install Flutter 3.41+.
2. Ensure Android Studio, Xcode, Visual Studio Desktop C++, and the Linux desktop toolchain are available for the platforms you plan to run.
3. Run `codex app-server --listen ws://127.0.0.1:8766` if it is not already running.
4. Run the Flutter app from the `app/` directory.

## Codex App-Server

Default local endpoint:

- WebSocket: `ws://127.0.0.1:8766`

## App

Run the client from the `app/` directory.

```bash
cd app
flutter pub get
flutter run
```

Desktop examples:

```bash
flutter run -d windows
flutter run -d macos
flutter run -d linux
```

## Runtime Configuration

The current app stores runtime settings in-app, including:

- App-server URL
- Data source mode (`direct` or `demo`)

No build-time flavor setup is required for local development.
