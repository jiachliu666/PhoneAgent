#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE' >&2
Usage:
  start_rpc_bridge.sh --udid <SIMULATOR_UDID> --token <TOKEN> [--port <PORT>] [--derived-data <PATH>]

Notes:
  - This uses an .xctestrun file so PHONEAGENT_* values actually reach the UI test process.
  - The bridge runs until you call the RPC method "stop".
USAGE
}

UDID=""
PORT="45678"
TOKEN=""
DERIVED_DATA=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --udid)
      UDID="${2:-}"; shift 2;;
    --port)
      PORT="${2:-}"; shift 2;;
    --token)
      TOKEN="${2:-}"; shift 2;;
    --derived-data)
      DERIVED_DATA="${2:-}"; shift 2;;
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

if [[ -z "$TOKEN" ]]; then
  echo "--token is required (PHONEAGENT_RPC_TOKEN is mandatory)" >&2
  usage
  exit 2
fi

if [[ -z "$DERIVED_DATA" ]]; then
  DERIVED_DATA="$(mktemp -d /tmp/phoneagent_dd_rpc.XXXXXX)"
else
  mkdir -p "$DERIVED_DATA"
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
XCTESTRUN_PATH=""

echo "Derived data: $DERIVED_DATA" >&2

is_simulator_udid() {
  python3 - "$UDID" <<'PY'
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

XCODEBUILD_CODESIGN_ARGS=()
if is_simulator_udid >/dev/null 2>&1; then
  # Simulator builds don't need signing; disabling it avoids requiring a configured signing identity.
  XCODEBUILD_CODESIGN_ARGS=(CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO)
fi

XCODEBUILD_ARGS=(
  xcodebuild
  build-for-testing
  -project "$ROOT_DIR/PhoneAgent.xcodeproj"
  -scheme "PhoneAgent"
  -destination "id=$UDID"
  -derivedDataPath "$DERIVED_DATA"
)
if ((${#XCODEBUILD_CODESIGN_ARGS[@]})); then
  XCODEBUILD_ARGS+=("${XCODEBUILD_CODESIGN_ARGS[@]}")
fi
"${XCODEBUILD_ARGS[@]}"

XCTESTRUN_PATH="$(ls -1 "$DERIVED_DATA/Build/Products/"*.xctestrun | head -n 1)"
if [[ -z "$XCTESTRUN_PATH" ]]; then
  echo "Failed to locate .xctestrun under: $DERIVED_DATA/Build/Products" >&2
  exit 1
fi

python3 "$ROOT_DIR/scripts/patch_xctestrun_env.py" "$XCTESTRUN_PATH" \
  "PHONEAGENT_MODE=rpc" \
  "PHONEAGENT_RPC_PORT=$PORT" \
  "PHONEAGENT_RPC_TOKEN=$TOKEN"

echo "PHONEAGENT_RPC_PORT=$PORT" >&2

xcodebuild test-without-building \
  -xctestrun "$XCTESTRUN_PATH" \
  -destination "id=$UDID" \
  -only-testing:PhoneAgentUITests/PhoneAgent/testMain
