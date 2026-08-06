# Neon Notch

[![CI](https://github.com/T0minh0/Neon-notch/actions/workflows/ci.yml/badge.svg)](https://github.com/T0minh0/Neon-notch/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
![Platform: macOS 26+](https://img.shields.io/badge/platform-macOS%2026%2B-000000?logo=apple)

Neon Notch is a native SwiftUI utility that turns a MacBook notch into a private, local control surface for coding agents, Spotify, system metrics, and recent clipboard items.

> **Version 0.2 is early alpha:** Neon Notch is actively evolving. Expect rough edges, changing integration behavior, and no compatibility guarantee between pre-release versions. The application UI currently remains Portuguese.

![Expanded Neon Notch panel](docs/assets/neon-notch-hero.png)

## Highlights

- Follow recent Codex and Claude Code activity, including attention-needed states.
- Install a small local helper and merge hooks through the app's onboarding or Settings.
- Control Spotify, review metrics, and keep a short, local clipboard history from one panel.
- Use the default global shortcut, `Control + Option + Space`, or set your own.
- Keep data on your Mac: no analytics, remote telemetry, or account is required.

## Requirements

- macOS 26 or later
- Xcode 26.6 or later with Swift 6.3 support
- An Apple Silicon (`arm64`) MacBook is the primary supported architecture; a built-in notch provides the intended presentation (the app can still build without one)

## Build from source

The canonical Debug build workflow builds the app and its `NeonNotchHook` helper without signing or launching your personal installation:

```bash
./script/build_and_run.sh --build-only
```

The generated bundle is at `DerivedData/Build/Products/Debug/Neon Notch.app`. Omit `--build-only` only when you want the script to open the Debug app after building.

For a signed personal Release install, first create the local signing identity and then run the installer.

> **Before running local signing:** `setup_local_signing.sh` creates a self-signed certificate and private key valid for ten years, imports them into your login keychain, and adds the certificate there as a trusted root. Review the [installation guide](docs/installation.md), including the Keychain Access removal steps, before continuing.

```bash
./script/setup_local_signing.sh
./script/build_and_install.sh
```

The Release script installs to `~/Applications`, signs the helper before the app, verifies the bundle, and keeps the previous app bundle for recovery. It intentionally does not use ad-hoc signing. See the [installation guide](docs/installation.md) before running it.

## Onboarding and permissions

On first launch, complete or defer the in-app onboarding. It checks the Release install location, installs the local helper, configures Codex and Claude Code, requests notifications, tests Spotify and Terminal Automation, and can enable launch at login.

Codex requires an explicit trust decision: after configuring its hook, run `/hooks` in Codex, inspect `NeonNotchHook`, and confirm trust yourself. The app never automates that approval. Claude Code hooks take effect in a new session after configuration.

Notifications and Automation are optional. If macOS denies either, use the recovery actions in Settings or the [troubleshooting guide](docs/troubleshooting.md).

## Privacy and limitations

Neon Notch stores its working data locally in Application Support. The helper stores selected event metadata verbatim, including identifiers and working-directory paths; only its short summary passes the sanitizer. Independently of hooks, the app observes local Codex and Claude agent state from startup, even before onboarding is complete. Clipboard collection skips concealed and transient types and defaults to excluding common password-manager apps. Spotify artwork is cached locally.

The app is not sandboxed by design because it integrates with local tools and Automation. It is not a security boundary, does not sync data, and does not guarantee that external Codex, Claude Code, Spotify, or macOS APIs will remain compatible. Read [privacy and security](docs/privacy-security.md) for details.

## Architecture

The SwiftUI app uses an AppKit `NSPanel` bridge for notch-adjacent presentation. A bundled `NeonNotchHook` helper receives configured Codex and Claude Code hook events and appends selected metadata plus a sanitized short summary to local JSONL; a separate provider observation path and other local services reduce state for the panel. See the [architecture guide](docs/architecture.md) for the component and data-flow detail.

## Project guide

- [Installation](docs/installation.md)
- [Architecture](docs/architecture.md)
- [Privacy and security](docs/privacy-security.md)
- [Troubleshooting](docs/troubleshooting.md)
- [Design QA](docs/design-qa.md)
- [Contributing](CONTRIBUTING.md)
- [Support](SUPPORT.md)
- [Security policy](SECURITY.md)
- [Changelog](CHANGELOG.md)
- [License](LICENSE)

## Testing

Run the canonical macOS test suite from the repository root:

```bash
xcodebuild \
  -project NeonNotch.xcodeproj \
  -scheme NeonNotch \
  -configuration Debug \
  -derivedDataPath DerivedData \
  -destination 'platform=macOS,arch=arm64' \
  CODE_SIGNING_ALLOWED=NO \
  test
```
