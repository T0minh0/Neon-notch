# Privacy and security

## Privacy model

Neon Notch is local-first. It does not require an account and does not send analytics, telemetry, clipboard history, agent events, or Spotify metadata to a Neon Notch service.

The agent helper is deliberately narrow. It persists supported event metadata such as source, event type, identifiers, working directory, timestamp, and a short sanitized summary. It does not intentionally retain prompts, model responses, shell commands, or tool arguments. Summaries are redacted for common API-token patterns, normalized, and length-limited before storage.

Clipboard history is stored locally. Concealed, transient, and auto-generated pasteboard types are ignored, and the default exclusion list includes common password managers. You can configure excluded applications in the app. File clipboard entries are references, not copied file contents. Spotify artwork is cached only on the local device.

## Access and permissions

Notifications are optional and are used for agent attention alerts. Spotify and Terminal Automation are optional and require macOS approval. Codex trust is always an explicit decision made in Codex after you inspect the hook. The app's onboarding and Settings expose diagnostic and recovery actions for each integration.

## Security boundaries

The app is not sandboxed because it needs local hook, clipboard, and Automation access. Treat it as a desktop utility with access appropriate to those features, not as a security boundary. Review any generated hook changes before approving them, keep the app and its dependencies updated, and avoid enabling integrations you do not need.

Event logs and snapshots are local operational data. They are retained for a limited period and compacted by the app, but should still be treated as private data on a shared Mac. See [troubleshooting](troubleshooting.md) for safe repair steps.

To report a vulnerability, follow the repository's [security policy](../SECURITY.md).
