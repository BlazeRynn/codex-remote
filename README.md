# Codex Remote

[Chinese README](README.zh-CN.md)

`Codex Remote` is a Flutter companion for local Codex sessions. Use it to
browse threads, follow realtime updates, continue turns, respond to approvals,
and steer or interrupt an active session from desktop or mobile.

## Repository Contents

- `app/`: Flutter client for Android, iOS, Windows, macOS, and Linux
- `proxy/`: local stdio tee proxy that mirrors a VS Code Codex session to
  WebSocket clients

## Requirements

- A local `codex` CLI installation
- Flutter and the platform toolchain you plan to run
- `dart` available on `PATH` if you use the source proxy launchers in `proxy/`

## Choose A Connection Mode

### 1. Direct App-Server Connection

Use this when the app can talk to a Codex `app-server` directly.

1. Start the local app-server:

   ```bash
   codex app-server --listen ws://127.0.0.1:8766
   ```

2. Run the Flutter app:

   ```bash
   cd app
   flutter pub get
   flutter run
   ```

3. In the app settings, set the Codex app-server URL:

| Target | URL |
| --- | --- |
| Desktop / iOS Simulator | `ws://127.0.0.1:8766` |
| Android Emulator | `ws://10.0.2.2:8766` |

### 2. Share The Same VS Code Session

Use this when the app should attach to the exact live session already used by
the VS Code Codex extension.

1. Point the VS Code setting `chatgpt.cliExecutable` to one of these launchers:

   - Windows source launcher: `proxy/codex-proxy.cmd`
   - Windows built launcher: `proxy/build/codex-proxy.exe`
   - macOS / Linux source launcher: `proxy/codex-proxy`

2. Configure VS Code:

   - open Settings and search for `chatgpt.cliExecutable`, or
   - open `settings.json` and set it directly

   Example:

   ```json
   {
     "chatgpt.cliExecutable": "<path-to-your-repo>\\proxy\\codex-proxy.cmd"
   }
   ```

3. Do not append `app-server` or `--listen` yourself in the setting. The proxy
   only intercepts the normal `codex app-server` launch that VS Code starts on
   its own.

4. On macOS or Linux, make the source launcher executable:

   ```bash
   chmod +x proxy/codex-proxy
   ```

5. If the real `codex` executable is not on `PATH`, set
   `CODEX_PROXY_REAL_CLI` before starting VS Code so the proxy can find it.

6. Use Codex in VS Code as usual. The proxy mirrors that same session to:

   ```text
   ws://127.0.0.1:8767
   ```

7. In the app settings, set the Codex app-server URL:

| Target | URL |
| --- | --- |
| Desktop / iOS Simulator | `ws://127.0.0.1:8767` |
| Android Emulator | `ws://10.0.2.2:8767` |

## How To Use The App

### First Launch

1. Start the local `app-server` or the VS Code shared-session proxy.
2. Open the app and enter `Codex settings`.
3. Fill in the Codex app-server URL, then choose `Save configuration`.
4. Return to the main page and use `Refresh` if the thread list does not load
   immediately.

### Thread List Page

The main page is the session list. From the top bar you can:

- `Refresh`: reload the thread list and current connection state
- `New Session`: create a new Codex session
- `App-server Logs`: inspect live RPC requests, responses, errors, and events
- `Codex settings`: change the endpoint, theme, language, and notification
  preferences

Tap a session to open its detail view. The list also supports archiving or
restoring sessions.

### Create A New Session

1. Click `New Session`.
2. Enter the first prompt for the session.
3. Optionally select a model.
4. Choose the session mode:

   - `No file changes`
   - `Current project only`
   - `Includes outside project`

5. Choose a workspace:

   - provider default workspace
   - one of the workspaces already used by existing sessions
   - a path from the directory tree

6. Click `Create`.

### Work Inside A Session

The session detail page shows the conversation, operation timeline, live
connection state, and pending runtime requests.

At the bottom composer you can:

- type the next prompt
- switch model
- switch permission mode for follow-up prompts
- add an image or file attachment
- paste supported clipboard content into the composer
- send the prompt

If a turn is currently running and the composer is empty, the send button turns
into `Stop response` and interrupts the active turn.

### Handle Requests And Debug Issues

- Approval, user-input, and MCP requests appear in the pending requests area at
  the bottom of a session.
- Simple requests can be answered inline. Structured requests open a form dialog
  and are submitted with `Submit`.
- If a request includes a URL, the app can copy it to the clipboard.
- `App-server Logs` provides a live RPC trace with search and filters for
  calls, returns, errors, and events, which is the main page to inspect when a
  session does not behave as expected.

### Proxy Checklist For VS Code

If the app does not attach to the same live session as VS Code, check these
first:

- `chatgpt.cliExecutable` points to `proxy/codex-proxy.cmd`,
  `proxy/codex-proxy`, or your built proxy executable
- you did not put `app-server` or `--listen` into that setting
- the real `codex` CLI is on `PATH`, or `CODEX_PROXY_REAL_CLI` is set
- the app is connected to `ws://127.0.0.1:8767` or the mirror URL you overrode
- `App-server Logs` and proxy stderr output show the proxy actually started

## What The App Can Do

- Browse thread lists and thread details
- Follow realtime updates and the operation timeline
- Start threads and send follow-up prompts
- Steer or interrupt active turns
- Review approval, user-input, and MCP requests
- Switch theme and language, and enable notifications for approvals, final
  answers, and realtime errors

## Proxy Options

The proxy mirror defaults to `ws://127.0.0.1:8767`.

Optional environment variables:

- `CODEX_PROXY_MIRROR_WS`: override the mirror WebSocket endpoint
- `CODEX_PROXY_REAL_CLI`: set an explicit path to the real `codex` executable
- `CODEX_PROXY_DEBUG=1`: print proxy logs to `stderr`

## More Module Docs

- [`app/README.md`](app/README.md)
- [`proxy/README.md`](proxy/README.md)

## Notes

- The app talks to Codex over WebSocket JSON-RPC.
- This repo does not include a relay server or public exposure layer.
- If you need remote access, put your own network boundary in front of the
  local endpoint, such as `frp`.
