# Architecture

Neon Notch is a native macOS application built with SwiftUI, with a small AppKit bridge where macOS panel behavior requires it.

## Components

| Component | Responsibility |
| --- | --- |
| `NeonNotch` | SwiftUI app, notch panel, Settings, onboarding, and local services. |
| `NeonNotchHook` | Command-line helper that accepts hook events on standard input and appends selected event metadata plus a sanitized short summary to local JSONL. |
| `NeonNotchTests` | Tests for state reduction, sanitation, hook compatibility, retention, shortcuts, media commands, and integrations. |
| `script/` | Canonical Debug build/run, local signing/install, and image utility workflows. |

## Data flow

1. Codex or Claude Code invokes `NeonNotchHook` through a configured local hook. Codex requires the user to approve that hook explicitly.
2. The helper writes selected metadata verbatim—event/subtype, session and agent identifiers, working directory, and timestamp—plus a short sanitized summary to the app's local JSONL queue.
3. `AgentEventStore` reads, deduplicates, retains, and compacts those events.
4. Independently, `AgentMonitorService` starts provider observation when the non-demo app launches, even before onboarding is complete. It discovers Codex `state_*.sqlite` catalogs, queries recent rows read-only, inspects at most the final 128 KiB of referenced rollout files, and runs `claude agents --json --all`. Raw SQLite rows, rollout text, and Claude JSON are inspected in memory rather than copied; derived identifiers, paths/project information, timestamps, and status snapshots may be persisted.
5. `AgentMonitorService` reconciles hook events, provider observations, and persisted snapshots into displayable agent state. Provider observation refreshes periodically while the app runs. Codex hook trust gates hook execution only, not provider observation.
6. `AppModel` coordinates the panel, settings, notifications, clipboard, media, and diagnostics.

## Local state

Application data is stored under the user's Application Support directory in a `NeonNotch` folder. It includes the event queue, snapshots, deduplication receipts, clipboard cache, helper binary, integration backups, and Spotify artwork cache. The app does not operate a server or synchronization service.

## UI and platform integration

`NotchPanelController` uses an AppKit `NSPanel` to manage notch-adjacent presentation and frame changes. SwiftUI renders the panel content, control center, onboarding, and settings. Services use macOS frameworks for global shortcuts, notifications, pasteboard observation, login items, and optional AppleScript Automation.

For visual implementation checks, see [Design QA](design-qa.md).
