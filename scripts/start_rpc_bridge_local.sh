#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE' >&2
Usage:
  start_rpc_bridge_local.sh --udid <UDID>

What this does:
  - Runs the PhoneAgent UI-test RPC server.
  - For physical devices (USB or Xcode "Connect via network"), starts a localhost-only forwarder
    so you can always connect to 127.0.0.1:45678 and the RPC port is not exposed to the LAN.
    It prefers the CoreDevice tunnel (*.coredevice.local) and falls back to USB via usbmux when available.

Requirements (physical device):
  - python3
  - (USB only) pip package: pymobiledevice3 (install into ./.venv)
USAGE
}

UDID=""
RPC_PORT="45678"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --udid)
      UDID="${2:-}"; shift 2;;
    -h|--help)
      usage; exit 0;;
    *)
      echo "Unknown arg: $1" >&2
      usage
      exit 2;;
  esac
done

if [[ -z "$UDID" ]]; then
  echo "--udid is required" >&2
  usage
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

PYTHON="python3"
if [[ -x "$ROOT_DIR/.venv/bin/python" ]]; then
  PYTHON="$ROOT_DIR/.venv/bin/python"
fi

is_simulator_udid() {
  "$PYTHON" - "$UDID" <<'PY'
import json
import subprocess
import sys

udid = sys.argv[1].lower()
raw = subprocess.check_output(["xcrun", "simctl", "list", "devices", "-j"])
data = json.loads(raw)
for _, devices in (data.get("devices") or {}).items():
    for d in devices or []:
        if str(d.get("udid", "")).lower() == udid:
            print("simulator")
            raise SystemExit(0)
raise SystemExit(1)
PY
}

FORWARD_PID=""
cleanup() {
  if [[ -n "${FORWARD_PID:-}" ]]; then
    kill "$FORWARD_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM

# Cache simulator check; calling it twice is slow and hits xcrun each time.
IS_SIMULATOR=0
if is_simulator_udid >/dev/null 2>&1; then
  IS_SIMULATOR=1
fi

if ((IS_SIMULATOR)); then
  echo "Simulator detected; use RPC host 127.0.0.1:$RPC_PORT (wait for PHONEAGENT_RPC_READY ... in logs)" >&2
else
  echo "Physical device detected; starting localhost forward: 127.0.0.1:$RPC_PORT -> device:$RPC_PORT" >&2
  "$PYTHON" "$ROOT_DIR/scripts/forward_rpc_localhost.py" \
    --udid "$UDID" &
  FORWARD_PID="$!"

  # Give the forwarder a moment to bind; fail fast if it died (missing deps, port in use, etc).
  sleep 0.2
  kill -0 "$FORWARD_PID" 2>/dev/null || { echo "Port forwarder failed to start." >&2; exit 1; }

  echo "Port forwarder is listening on 127.0.0.1:$RPC_PORT (wait for PHONEAGENT_RPC_READY ... in logs)" >&2
fi

# Start the test-hosted JSON-RPC server via a single UI-test entrypoint.
XCODEBUILD_CODESIGN_ARGS=()
if ((IS_SIMULATOR)); then
  # Simulator builds don't need signing; disabling it avoids requiring a configured signing identity.
  XCODEBUILD_CODESIGN_ARGS=(CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO)
fi

XCODEBUILD_ARGS=(
  xcodebuild
  test
  -project "$ROOT_DIR/PhoneAgent.xcodeproj"
  -scheme "PhoneAgent"
  -destination "id=$UDID"
  -only-testing:PhoneAgentUITests/PhoneAgent/testMain
)
if ((${#XCODEBUILD_CODESIGN_ARGS[@]})); then
  XCODEBUILD_ARGS+=("${XCODEBUILD_CODESIGN_ARGS[@]}")
fi

"${XCODEBUILD_ARGS[@]}"
