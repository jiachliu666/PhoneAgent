#!/usr/bin/env python3
"""
Forward a local TCP port on macOS to a TCP port on an iOS device via usbmuxd.

Important: this binds ONLY on 127.0.0.1 so the forwarded port is not exposed to the LAN.

This is intended to be used with the PhoneAgent UI-test RPC bridge, where the device-side
server does not accept LAN connections.
"""

from __future__ import annotations

import argparse
import sys


def die(msg: str, code: int = 2) -> None:
    print(msg, file=sys.stderr)
    raise SystemExit(code)


def main() -> None:
    ap = argparse.ArgumentParser(
        description="Forward localhost:<local-port> to <udid>:<device-port> over usbmux (USB or Xcode network debugging)."
    )
    ap.add_argument("--udid", required=True, help="Device UDID / serial")
    ap.add_argument("--local-port", required=True, type=int, help="Local port to listen on (binds 127.0.0.1 only)")
    ap.add_argument("--device-port", required=True, type=int, help="Device port to connect to")
    ap.add_argument(
        "--connection-type",
        choices=["USB", "Network"],
        default=None,
        help="Optional: force usbmux connection type. Default prefers USB if available.",
    )
    ap.add_argument(
        "--usbmux",
        default=None,
        help="Optional: usbmuxd address (advanced). Leave empty for default.",
    )
    args = ap.parse_args()

    try:
        from pymobiledevice3.tcp_forwarder import UsbmuxTcpForwarder
    except Exception as e:  # pragma: no cover
        die(
            "Missing Python dependency: pymobiledevice3\n"
            "\n"
            "Install it with:\n"
            "  python3 -m venv .venv\n"
            "  ./.venv/bin/python -m pip install -U pip\n"
            "  ./.venv/bin/python -m pip install pymobiledevice3\n"
            "\n"
            f"Original import error: {e}"
        )

    forwarder = UsbmuxTcpForwarder(
        args.udid,
        args.device_port,
        args.local_port,
        usbmux_connection_type=args.connection_type,
        usbmux_address=args.usbmux,
    )

    print(
        f"Forwarding 127.0.0.1:{args.local_port} -> {args.udid}:{args.device_port} via usbmux",
        file=sys.stderr,
    )

    try:
        forwarder.start(address="127.0.0.1")
    except KeyboardInterrupt:
        forwarder.stop()


if __name__ == "__main__":
    main()
