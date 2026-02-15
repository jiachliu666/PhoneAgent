# PhoneAgent

This is an iPhone using Agent that uses OpenAI models to get things done on a phone, spanning across multiple apps, very similar to a human user. It was built during an OpenAI hackathon last year.

# Demo

[![image](https://github.com/user-attachments/assets/a25cc506-47a0-4fae-93c4-cf890b236c13)](https://www.youtube.com/shorts/4rnv6dN-2Lg)

# What you can do
Example prompts:
- Click a new selfie and send it to {Contact name} with a haiku about the weekend
- Download {app name} from the App Store
- Send a message to {Contact name}: my flight is DL 1715 and Call an Uber X to SFO
- Open Control Center and enable the torch

# RPC Bridge

You can drive iOS UI via the UI-test JSON-RPC bridge (newline-delimited JSON). See `skills/iphone-rpc-control/SKILL.md` for a full workflow.

Helper CLI: use `./scripts/rpc.py` to make calls without hand-writing JSON / `nc`:

```bash
./scripts/rpc.py open-app com.apple.Preferences
./scripts/rpc.py get-tree | head
```

Security: the RPC server rejects direct LAN peers; use a localhost-only tunnel/port-forward:

- Simulator: connect to `127.0.0.1:45678`
- Physical iPhone (USB or Xcode "Connect via network"): run `./scripts/start_rpc_bridge_local.sh ...` and connect to `127.0.0.1:45678` (the script starts a localhost-only forwarder that prefers the CoreDevice tunnel and falls back to USB via usbmux; `pymobiledevice3` is only required for the USB fallback).

For the full RPC method reference and recommended operating loop, see `skills/iphone-rpc-control/SKILL.md`.

# Features

- The model can see an app's accessibilty tree
- It can tap, swipe, scroll, type and open apps
- You can follow up on a task by replying to the completion notification
- You can talk to the agent using the microphone button
- There is an optional Always On mode that listens for prompts starting with a wake word (Agent by default) even when the app is backgroundded. So you can say something like "Agent, open Settings"
- The app persists your OpenAI API key securely on your device's keychain

# How it works

iOS apps are sandboxed, so this project uses Xcode's UI testing harness to inspect and interact with apps and the system. (no jailbreak required).

The agent is powered by OpenAI's gpt-4.1 model. It is surprisingly good at using the iPhone just with the accessibility contents of an app. It access to these tools:

- getting the contents of the current app
- tapping on a UI element
- typing in a text field
- opening an app

The host app communicates with the UI test runner via the same newline-delimited JSON RPC bridge (loopback), sending `set_api_key` and `submit_prompt`.

# Limitations
- Keyboard input can be improved
- Capturing the view hierarchy while an animation is inflight confuses the model
- The model doesn't wait for long running tasks to complete, so it might give up prematurely.
- The model doesn't see an image representation of the screen yet, but it's possible to do it via XCTest APIs.

# Disclaimer
- This is experimental software
- This is a personal project
- Recommend running this in an isolated environment
- The app contents are sent to OpenAI's API
- The model can get things wrong sometimes
