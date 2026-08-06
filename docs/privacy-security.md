# Privacy and security

## Privacy model

Neon Notch is local-first. It does not require an account and does not send analytics, telemetry, clipboard history, agent events, or Spotify metadata to a Neon Notch service.

The agent helper is deliberately narrow. It persists selected event metadata such as source, event name and subtype, session and agent identifiers, working directory, and timestamp verbatim. Only the short summary passes the sanitizer: it is redacted for common API-token patterns, normalized, and length-limited before storage. The helper does not intentionally select prompts, model responses, shell commands, or tool arguments for its record, but metadata such as identifiers and paths can still be sensitive.

Clipboard history is stored locally. Concealed, transient, and auto-generated pasteboard types are ignored, and the default exclusion list includes common password managers. You can configure excluded applications in the app. Stored clipboard payloads are not sanitized: text and URLs are retained in full, images are retained as encoded data up to 10 MB, and file entries retain full paths rather than copying file contents. Spotify artwork is cached only on the local device.

## Independent provider observation

In non-demo mode, observation begins whenever the app starts, including before onboarding is complete and whether or not hooks have been installed. After the initial scan, the app refreshes provider state about every 10 seconds while the panel is active and about every 30 seconds while it is collapsed.

- **Codex:** the app discovers `state_*.sqlite` catalogs in `~/.codex/` and `~/.codex/sqlite/`, queries up to 20 recent unarchived thread rows in read-only mode, and inspects the final 128 KiB of each referenced rollout file for attention/completion markers. A rollout tail may contain transcript content. The raw database rows and tail text are inspected in memory and are not copied to Neon Notch storage; derived snapshots retain identifiers, working-directory/project information, timestamps, and inferred status/reason.
- **Claude Code:** the app runs `claude agents --json --all`, parses the returned JSON, then uses at most the first 40 agent records and their process status to derive the same kind of snapshot. The raw command output is not copied to Neon Notch storage; selected derived fields are retained in snapshots.

Codex's explicit hook trust decision gates Codex executing `NeonNotchHook` only. It does not gate this independent provider observation path; only the Codex SQLite query itself is opened in read-only mode.

## Access and permissions

Notifications are optional and are used for agent attention alerts. Spotify and Terminal Automation are optional and require macOS approval. Codex trust is always an explicit decision made in Codex after you inspect the hook. The app's onboarding and Settings expose diagnostic and recovery actions for each integration.

## Security boundaries

The app is not sandboxed because it needs local hook, clipboard, and Automation access. Treat it as a desktop utility with access appropriate to those features, not as a security boundary. Review any generated hook changes before approving them, keep the app and its dependencies updated, and avoid enabling integrations you do not need.

## Retention and deletion

All paths below are inside `~/Library/Application Support/NeonNotch/`. Retention is implemented while the app runs; quitting the app before manual cleanup avoids racing a writer.

| Data | Location | Retention behavior | Deletion |
| --- | --- | --- | --- |
| Hook event log | `agent-events.jsonl` | On compaction, events older than 48 hours are removed and the log is capped at 5 MiB by dropping the oldest remaining records. Compaction runs at app startup, on wake, and approximately every five minutes while the app runs. | Quit the app and delete this file. New hook events recreate it while configured hooks remain active. |
| Agent snapshots | `agent-snapshots.json` | Only snapshots updated within the last 24 hours are loaded and persisted. There is no separate archive. | Quit the app and delete this file. Independent provider observation can recreate derived snapshots on the next launch. |
| Event deduplication receipts | `agent-event-receipts.json` | Receipts older than 48 hours are pruned when receipts are loaded or updated; the file is removed when none remain. | Quit the app and delete this file. It is recreated when hook events are recorded. |
| Unpinned clipboard entries | `clipboard.json` | Expire after exactly five hours. Each new capture trims the unpinned list to its 100 newest entries; unpinning does not reapply that cap until a later capture, so the list can temporarily exceed 100. Expiry is applied on load, wake, capture, and timers while the app runs. | Use **Clear** to remove all unpinned entries, delete individual entries, or quit the app and delete `clipboard.json`. |
| Pinned clipboard entries | `clipboard.json` | No automatic expiry or count limit. **Clear** preserves them. | Delete each pinned entry, or unpin it (an entry already older than five hours is removed immediately). Deleting `clipboard.json` while the app is quit removes all clipboard history. |
| Integration configuration backups | `backups/` | A complete existing Codex or Claude configuration is copied before Neon Notch changes or removes hooks. Backups have no automatic expiry or pruning. Because these are full configuration copies, they may include unrelated hooks, paths, environment values, or credentials. | After confirming that no rollback is needed, quit the app and delete individual backups or the `backups/` directory. Treat deleted backup files as sensitive. |
| Spotify artwork | `artwork-cache/` | Each accepted download is at most 10 MB, but cached artwork has no automatic expiry or total-size pruning. | Quit the app and delete files in `artwork-cache/`; the directory and needed artwork are recreated later. |

### Full local cleanup

Removing integrations is not the same as erasing local data. For a complete removal:

1. Disable launch at login, then use **Settings → Integrations → Remove** so Neon Notch removes only its own handlers from `~/.codex/hooks.json` and `~/.claude/settings.json`. Do not delete those user-owned configuration files wholesale.
2. Quit the app, then delete `~/Library/Application Support/NeonNotch/`. This clears the tabled data and installed helper; configured hooks or a running app could otherwise recreate files.
3. If you also want to reset preferences, run `defaults delete com.cammis.NeonNotch`. macOS manages this defaults domain; it includes onboarding, exclusions, notifications, reduced-motion, shortcut, and diagnostic preferences.
4. Remove `~/Applications/Neon Notch.app`, `~/Applications/Neon Notch.previous.app`, and repository-local `DerivedData/` if present.
5. If you created the local signing identity, follow the [Keychain Access removal steps](installation.md#local-signing-warning).

See [troubleshooting](troubleshooting.md) for repair steps.

To report a vulnerability, follow the repository's [security policy](../SECURITY.md).
