# Installation

## Debug build

From the repository root, run:

```bash
./script/build_and_run.sh --build-only
```

This canonical build command builds the app and `NeonNotchHook`, embeds the helper in the Debug app bundle, and leaves the output at `DerivedData/Build/Products/Debug/Neon Notch.app`. Omit `--build-only` only when you want the script to open the Debug app after building.

## Signed personal installation

Neon Notch's Release installation is designed for a local, personal signing identity.

### Local-signing warning

Before you run the setup script, understand that it creates a self-signed code-signing certificate and its private key, valid for ten years. It imports that identity into your login keychain and adds the certificate there as a trusted root. This changes your local trust settings. The identity is only for your personal installation; it is not an Apple Developer ID certificate and does not make a distributable or notarized build.

The script uses the `openssl` found on `PATH`. It feature-detects whether `openssl pkcs12` supports `-legacy`: OpenSSL 3 keeps the compatibility option, while macOS's bundled LibreSSL exports the archive without the unsupported flag.

To remove the identity safely, quit Neon Notch, open **Keychain Access**, select the **login** keychain, search for `Neon Notch Local Code Signing`, and delete the certificate/identity together with its associated private key. Confirm the Keychain Access prompt. Existing builds signed by that identity will no longer be trusted; rerun the setup script only if you want to create a new identity.

Read the script before using it, and do not use this identity to sign software you intend to distribute. Then create it once:

```bash
./script/setup_local_signing.sh
```

Then build, sign, verify, and install:

```bash
./script/build_and_install.sh
```

The installer places the app at `~/Applications/Neon Notch.app` and retains the previous app at `~/Applications/Neon Notch.previous.app` after a successful replacement.

## First launch

Complete the onboarding in the app:

1. Confirm the Release app is running from `~/Applications` if you use the signed install.
2. Install or repair the local helper.
3. Configure Codex and/or Claude Code.
4. Decide whether to allow notifications and Spotify or Terminal Automation.
5. Optionally enable launch at login.

For Codex, run `/hooks` afterwards, inspect the `NeonNotchHook` configuration, and explicitly confirm trust. For Claude Code, start a new session after configuring hooks.

See [troubleshooting](troubleshooting.md) if a diagnostic remains incomplete.
