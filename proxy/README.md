# codex-proxy

`codex-proxy` is a local `stdio tee` proxy for the VS Code Codex extension.

It keeps VS Code on its normal private `stdio` app-server flow, but mirrors that
same JSON-RPC session to a local websocket so another client can observe or
attach to the live thread stream.

## What It Solves

- VS Code expects to own a private `codex app-server` child process over `stdio`
- Replacing that with a shared websocket backend breaks the extension's normal assumptions
- The Flutter client still needs a way to see the same live session that VS is using

`codex-proxy` now does this instead:

```text
VS Code <-> stdio <-> codex-proxy <-> stdio <-> real codex app-server
                      |
                      +-> ws://127.0.0.1:8767
```

So VS keeps talking to a normal private app-server, while the proxy mirrors that
same message stream over websocket.

## Default Mirror Endpoint

```text
ws://127.0.0.1:8767
```

Override it with:

```text
CODEX_PROXY_MIRROR_WS=ws://127.0.0.1:9000
```

## VS Code Setup

Point `chatgpt.cliExecutable` to one of:

```text
Windows source launcher: proxy/codex-proxy.cmd
macOS / Linux source launcher: proxy/codex-proxy
Optional Windows local build output: proxy/build/codex-proxy.exe
Optional macOS / Linux local build output: proxy/build/codex-proxy
```

When VS Code runs `codex app-server`, the proxy will:

1. Start the real `codex app-server` over `stdio`
2. Pass VS Code `stdin/stdout` through unchanged
3. Expose the mirrored session on `ws://127.0.0.1:8767`

On macOS and Linux, make the source launcher executable before using it:

```bash
chmod +x proxy/codex-proxy
```

## Flutter Setup

If you want Flutter to watch or drive the same live VS session, point the app to:

```text
ws://127.0.0.1:8767
```

If you want direct standalone mode instead, keep pointing Flutter at a normal
websocket app-server such as:

```text
ws://127.0.0.1:8766
```

## Optional Environment Variables

- `CODEX_PROXY_MIRROR_WS`: websocket mirror endpoint for secondary clients
- `CODEX_PROXY_REAL_CLI`: explicit path to the real `codex` executable
- `CODEX_PROXY_DEBUG=1`: print proxy logs to `stderr`

## Notes

- The proxy does not change how VS Code talks to Codex; VS still uses a private stdio child.
- A Flutter client connected to the mirror websocket is sharing the same live Codex session, not a separate backend instance.
- The proxy still does not tell Flutter which thread is currently selected in the VS UI; it only mirrors the protocol stream.
