# Troubleshooting

## The app builds but the helper is missing

Use the canonical build script rather than launching a product from an arbitrary build location:

```bash
./script/build_and_run.sh --build-only
```

It embeds `NeonNotchHook` in the app bundle. In the app, open Settings and use **Install / repair helper** if its diagnostic is incomplete.

## Codex or Claude Code shows no activity

Confirm that the relevant tool is installed and then configure the integration from onboarding or Settings. Codex requires a manual `/hooks` review and trust confirmation. Claude Code requires a new session after hook configuration. Use the integration diagnostic to identify whether the helper, configuration, or provider is missing.

## Notifications or Automation are denied

Open Settings in Neon Notch and use the diagnostic's recovery action. macOS permissions are managed in System Settings:

- Notifications: **Notifications → Neon Notch**.
- Spotify or Terminal: **Privacy & Security → Automation → Neon Notch**.

You can leave these permissions disabled; the corresponding optional feature will simply remain unavailable.

## The signed install does not replace the current app

Run the installer only after creating the local signing identity with `./script/setup_local_signing.sh`. The installer refuses to replace an app with a different designated requirement and refuses to overwrite a running app it cannot stop. Review its output, quit the installed app, and rerun the command. The previous bundle is retained at `~/Applications/Neon Notch.previous.app` after a successful update.

## Tests fail locally

Ensure the documented Xcode and macOS requirements are installed, then run the [canonical test command](../README.md#testing) from the repository root. Clean only generated `DerivedData` if a stale local build is implicated; do not delete application-support data unless you intend to remove local history and integration backups.

If you find a reproducible bug, include your macOS version, Xcode version, and safe reproduction steps in an [issue](../SUPPORT.md).
