# Installation

## Debug build

From the repository root, run:

```bash
./script/build_and_run.sh --build-only
```

This canonical build command builds the app and `NeonNotchHook`, embeds the helper in the Debug app bundle, and leaves the output at `DerivedData/Build/Products/Debug/Neon Notch.app`. Omit `--build-only` only when you want the script to open the Debug app after building.

## Signed personal installation

Neon Notch's Release installation is designed for a local, personal signing identity. Create it once:

```bash
./script/setup_local_signing.sh
```

Then build, sign, verify, and install:

```bash
./script/build_and_install.sh
```

The installer places the app at `~/Applications/Neon Notch.app` and retains the previous app at `~/Applications/Neon Notch.previous.app` after a successful replacement.

### Local-signing warning

The signing script creates a self-signed identity in your login keychain. It is for your local installation only; it is not an Apple Developer ID certificate and does not make a distributable or notarized build. Read the script before using it, and do not use it to sign software you intend to distribute.

## First launch

Complete the onboarding in the app:

1. Confirm the Release app is running from `~/Applications` if you use the signed install.
2. Install or repair the local helper.
3. Configure Codex and/or Claude Code.
4. Decide whether to allow notifications and Spotify or Terminal Automation.
5. Optionally enable launch at login.

For Codex, run `/hooks` afterwards, inspect the `NeonNotchHook` configuration, and explicitly confirm trust. For Claude Code, start a new session after configuring hooks.

See [troubleshooting](troubleshooting.md) if a diagnostic remains incomplete.
