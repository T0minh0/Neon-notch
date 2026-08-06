# Architecture

Neon Notch is a native macOS application built with SwiftUI, with a small AppKit bridge where macOS panel behavior requires it.

## Components

| Component | Responsibility |
| --- | --- |
| `NeonNotch` | SwiftUI app, notch panel, Settings, onboarding, and local services. |
| `NeonNotchHook` | Command-line helper that accepts hook events on standard input and appends sanitized JSONL records locally. |
| `NeonNotchTests` | Tests for state reduction, sanitation, hook compatibility, retention, shortcuts, media commands, and integrations. |
| `script/` | Canonical Debug build/run, local signing/install, and image utility workflows. |

## Data flow

1. Codex or Claude Code invokes `NeonNotchHook` through a user-approved local hook.
2. The helper sanitizes supported metadata and writes an event to the app's local JSONL queue.
3. `AgentEventStore` reads, deduplicates, retains, and compacts those events.
4. `AgentMonitorService` reduces events and provider observations into displayable agent snapshots.
5. `AppModel` coordinates the panel, settings, notifications, clipboard, media, and diagnostics.

## Local state

Application data is stored under the user's Application Support directory in a `NeonNotch` folder. It includes the event queue, snapshots, deduplication receipts, clipboard cache, helper binary, integration backups, and Spotify artwork cache. The app does not operate a server or synchronization service.

## UI and platform integration

`NotchPanelController` uses an AppKit `NSPanel` to manage notch-adjacent presentation and frame changes. SwiftUI renders the panel content, control center, onboarding, and settings. Services use macOS frameworks for global shortcuts, notifications, pasteboard observation, login items, and optional AppleScript Automation.

For visual implementation checks, see [Design QA](design-qa.md).
