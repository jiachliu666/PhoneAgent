---
name: iphone-rpc-control
description: Control a connected iPhone or iOS simulator from macOS through PhoneAgent's UI-test JSON-RPC bridge. Use when users ask to automate iOS UI actions, inspect accessibility trees, toggle Settings switches, navigate apps, or capture screenshots by sending RPC methods like get_tree, get_screen_image, get_context, tap_element, enter_text, scroll, swipe, and open_app.
---

# iPhone RPC Control

Use this workflow to drive iOS UI through the PhoneAgent test bridge.

## Start the RPC bridge

1. Find available devices.

```bash
xcrun xctrace list devices
```

2. Start the test-hosted RPC server on a chosen port.

```bash
xcodebuild test \
  -project PhoneAgent.xcodeproj \
  -scheme PhoneAgent \
  -destination 'id=<DEVICE_UDID>' \
  -only-testing:PhoneAgentUITests/PhoneAgent/testMain \
  PHONEAGENT_MODE=rpc \
  PHONEAGENT_RPC_PORT=45678
```

3. Keep this `xcodebuild test` process running. It is the bridge.
4. Wait for `PHONEAGENT_RPC_PORT=<port>` in logs before sending RPC calls.
5. Confirm socket readiness before first RPC:

```bash
python3 - <<'PY'
import socket
s = socket.create_connection(("127.0.0.1", 45678), timeout=3)
s.close()
print("rpc-ready")
PY
```

## Resolve host and port

1. For physical iPhone, resolve hostname:

```bash
xcrun devicectl list devices
```

2. Prefer `<udid>.coredevice.local` or `<name>.coredevice.local` as the RPC host.
3. Use the port printed by the test runner.
4. On simulator, prefer `127.0.0.1`.
5. On physical devices, use `*.coredevice.local`.

## Send RPC calls

Send one newline-delimited JSON request at a time:

```bash
printf '%s\n' '{"id":1,"method":"get_tree","params":{}}' \
  | nc -w 4 <HOST> <PORT>
```

Inspect tree output:

```bash
printf '%s\n' '{"id":2,"method":"get_tree","params":{}}' \
  | nc -w 4 <HOST> <PORT> \
  | jq -r '.result.tree'
```

## Core operating loop

1. Call `get_tree`.
2. Identify the best target element in the tree (label/identifier) and copy its frame coordinate string.
3. Prefer coordinate-based actions (`tap_element` / `enter_text`) to match the non-skill agent behavior.
4. Use the returned `tree` from the action response to verify the UI changed as expected.
5. Repeat until complete.

Use `swipe` to reveal off-screen content, then use the returned `tree` (or call `get_tree` if needed).
Use one request at a time per server. Do not fire concurrent batches.
Split long keyboard input into chunks; do not send giant `enter_text` payloads in one call.

## RPC method reference

All RPC requests are newline-delimited JSON objects with this shape:

```json
{"id":1,"method":"<method>","params":{...}}
```

All success responses look like:

```json
{"id":1,"result":{...}}
```

### `get_tree`

- Does: Returns the accessibility tree of the currently focused app.
- Params: none.
- Returns: `{"tree": "<string>"}`

Example:
```json
{"id":1,"method":"get_tree","params":{}}
```

### `get_screen_image`

- Does: Captures the current screen as a base64-encoded PNG plus image dimensions (when available).
- Params: none.
- Returns: `{"screenshot_base64":"<base64>","metadata":{"width":<number>,"height":<number>}}`

Example:
```json
{"id":2,"method":"get_screen_image","params":{}}
```

### `get_context`

- Does: Convenience method that returns both the current accessibility tree and the current screen image.
- Params: none.
- Returns: `{"tree":"<string>","screenshot_base64":"<base64>","metadata":{"width":<number>,"height":<number>}}`

Example:
```json
{"id":3,"method":"get_context","params":{}}
```

### `open_app`

- Does: Brings the specified app to the foreground (and makes it the focused app for subsequent calls).
- Params: `bundle_identifier` (string, required). Example: `com.apple.Preferences`.
- Returns: `{"bundle_identifier":"<string>", "tree":"<string>"}`

Example:
```json
{"id":4,"method":"open_app","params":{"bundle_identifier":"com.apple.Preferences"}}
```

### `tap`

- Does: Taps an absolute point in the current app.
- Params: `x` (number, required), `y` (number, required). Coordinates are in absolute screen points as reported by the tree.
- Returns: `{"tree":"<string>"}`

Example:
```json
{"id":5,"method":"tap","params":{"x":120,"y":300}}
```

### `tap_element`

- Does: Taps the *center* of an element using its XCUI frame string from the accessibility tree.
- Params:
- `coordinate` (string, required). Must look like `{{x, y}, {w, h}}` (copied from the tree).
- `count` (integer, optional; default 1). Use 2 for double-tap.
- `longPress` (boolean, optional; default false). When true, performs a long-press gesture.
- Returns: `{"coordinate":"<string>", "count":<number>, "longPress":<bool>, "tree":"<string>"}`

Example:
```json
{"id":6,"method":"tap_element","params":{"coordinate":"{{20.0, 165.0}, {390.0, 90.0}}","count":1,"longPress":false}}
```

### `enter_text`

- Does: Taps the center of the target element (to focus it), waits briefly for the keyboard, then types the provided text followed by a newline (Return).
- Params:
- `coordinate` (string, required). Must look like `{{x, y}, {w, h}}` (copied from the tree).
- `text` (string, required).
- Returns: `{"coordinate":"<string>", "tree":"<string>"}`

Example:
```json
{"id":7,"method":"enter_text","params":{"coordinate":"{{33.0, 861.0}, {364.0, 38.0}}","text":"hello"}}
```

### `scroll`

- Does: Scrolls by dragging from a starting point by the provided deltas.
- Params: `x` (number, required), `y` (number, required), `distanceX` (number, required), `distanceY` (number, required).
- Returns: `{"tree":"<string>"}`

Example:
```json
{"id":8,"method":"scroll","params":{"x":215,"y":760,"distanceX":0,"distanceY":-460}}
```

### `swipe`

- Does: Swipes in a direction starting from a given point (implemented as a bounded drag gesture).
- Params: `x` (number, required), `y` (number, required), `direction` (string, required; one of `up`, `down`, `left`, `right`).
- Returns: `{"tree":"<string>"}`

Example:
```json
{"id":9,"method":"swipe","params":{"x":215,"y":760,"direction":"up"}}
```

### `stop`

- Does: Stops the RPC server test (ends the `xcodebuild test` session).
- Params: none.
- Returns: `{}`

Example:
```json
{"id":10,"method":"stop","params":{}}
```

## iOS app bundle IDs

- Settings: `com.apple.Preferences`
- Camera: `com.apple.camera`
- Photos: `com.apple.mobileslideshow`
- Messages: `com.apple.MobileSMS`
- Home Screen: `com.apple.springboard`

## Recovery playbook

1. If RPC hangs after `open_app`, restart the test-hosted server and retry with a known-good bundle id.
2. If taps fail due stale UI, call `get_tree` again and recalculate target.
3. If server becomes unresponsive, stop/restart `xcodebuild test` and resume from latest verified app state.

## End session

1. Send `stop` only when the task is complete.
2. If `stop` is not sent, terminate the `xcodebuild` session manually.
