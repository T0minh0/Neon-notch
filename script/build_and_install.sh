#!/bin/zsh
set -euo pipefail

readonly SCRIPT_DIRECTORY="${0:A:h}"
readonly PROJECT_DIRECTORY="${SCRIPT_DIRECTORY:h}"
readonly DERIVED_DIRECTORY="${PROJECT_DIRECTORY}/DerivedData"
readonly IDENTITY_NAME="Neon Notch Local Code Signing"
readonly INSTALL_DIRECTORY="${HOME}/Applications"
readonly INSTALLED_APP="${INSTALL_DIRECTORY}/Neon Notch.app"
readonly PREVIOUS_APP="${INSTALL_DIRECTORY}/Neon Notch.previous.app"
readonly STAGING_APP="${INSTALL_DIRECTORY}/.Neon Notch.app.installing-${$}"

cleanup_staging() {
  if [[ -d "${STAGING_APP}" ]]; then rm -rf -- "${STAGING_APP}"; fi
}
trap cleanup_staging EXIT

if ! security find-identity -v -p codesigning | grep -Fq "${IDENTITY_NAME}"; then
  print -u2 -r -- "Missing code-signing identity: ${IDENTITY_NAME}"
  print -u2 -r -- "Run ./script/setup_local_signing.sh first. Ad hoc signing is intentionally disabled."
  exit 1
fi

xcodebuild \
  -project "${PROJECT_DIRECTORY}/NeonNotch.xcodeproj" \
  -scheme NeonNotch \
  -configuration Release \
  -derivedDataPath "${DERIVED_DIRECTORY}" \
  CODE_SIGNING_ALLOWED=NO \
  build

readonly BUILT_APP="${DERIVED_DIRECTORY}/Build/Products/Release/Neon Notch.app"
readonly BUILT_HELPER="${DERIVED_DIRECTORY}/Build/Products/Release/NeonNotchHook"
readonly EMBEDDED_HELPER="${BUILT_APP}/Contents/Helpers/NeonNotchHook"

mkdir -p "${BUILT_APP}/Contents/Helpers"
cp "${BUILT_HELPER}" "${EMBEDDED_HELPER}"
chmod 755 "${EMBEDDED_HELPER}"

codesign --force --sign "${IDENTITY_NAME}" --options runtime --timestamp=none "${EMBEDDED_HELPER}"
codesign \
  --force \
  --sign "${IDENTITY_NAME}" \
  --options runtime \
  --timestamp=none \
  --entitlements "${PROJECT_DIRECTORY}/NeonNotch/NeonNotch.entitlements" \
  "${BUILT_APP}"

codesign --verify --deep --strict --verbose=2 "${BUILT_APP}"

readonly NEW_REQUIREMENT="$(codesign -d -r- "${BUILT_APP}" 2>&1 | sed -n 's/^designated => //p')"
if [[ -d "${INSTALLED_APP}" ]]; then
  readonly OLD_REQUIREMENT="$(codesign -d -r- "${INSTALLED_APP}" 2>&1 | sed -n 's/^designated => //p')"
  if [[ -n "${OLD_REQUIREMENT}" && "${OLD_REQUIREMENT}" != "${NEW_REQUIREMENT}" ]]; then
    print -u2 -r -- "The designated requirement changed; refusing to replace the installed app."
    print -u2 -r -- "Installed: ${OLD_REQUIREMENT}"
    print -u2 -r -- "New:       ${NEW_REQUIREMENT}"
    exit 1
  fi
fi

mkdir -p "${INSTALL_DIRECTORY}"
rm -rf -- "${STAGING_APP}"
ditto "${BUILT_APP}" "${STAGING_APP}"
codesign --verify --deep --strict --verbose=2 "${STAGING_APP}"

osascript -e 'tell application id "com.cammis.NeonNotch" to quit' >/dev/null 2>&1 || true
for _ in {1..20}; do
  if ! pgrep -f -- "${INSTALLED_APP}/Contents/MacOS/Neon Notch" >/dev/null; then
    break
  fi
  sleep 0.1
done
if pgrep -f -- "${INSTALLED_APP}/Contents/MacOS/Neon Notch" >/dev/null; then
  pkill -TERM -f -- "${INSTALLED_APP}/Contents/MacOS/Neon Notch"
  for _ in {1..20}; do
    if ! pgrep -f -- "${INSTALLED_APP}/Contents/MacOS/Neon Notch" >/dev/null; then
      break
    fi
    sleep 0.1
  done
fi
if pgrep -f -- "${INSTALLED_APP}/Contents/MacOS/Neon Notch" >/dev/null; then
  print -u2 -r -- "The installed app did not terminate; refusing to replace a running bundle."
  exit 1
fi

if [[ -d "${PREVIOUS_APP}" ]]; then
  rm -rf -- "${PREVIOUS_APP}"
fi
if [[ -d "${INSTALLED_APP}" ]]; then
  mv "${INSTALLED_APP}" "${PREVIOUS_APP}"
fi
mv "${STAGING_APP}" "${INSTALLED_APP}"

if ! open "${INSTALLED_APP}"; then
  rm -rf -- "${INSTALLED_APP}"
  if [[ -d "${PREVIOUS_APP}" ]]; then mv "${PREVIOUS_APP}" "${INSTALLED_APP}"; fi
  print -u2 -r -- "Launch failed; the previous version was restored."
  exit 1
fi

for _ in {1..30}; do
  if pgrep -f -- "${INSTALLED_APP}/Contents/MacOS/Neon Notch" >/dev/null; then
    print -r -- "Installed and launched ${INSTALLED_APP}"
    [[ -d "${PREVIOUS_APP}" ]] && print -r -- "Previous version kept at ${PREVIOUS_APP}"
    print -r -- "Designated requirement: ${NEW_REQUIREMENT}"
    exit 0
  fi
  sleep 0.1
done

rm -rf -- "${INSTALLED_APP}"
if [[ -d "${PREVIOUS_APP}" ]]; then
  mv "${PREVIOUS_APP}" "${INSTALLED_APP}"
  open "${INSTALLED_APP}" >/dev/null 2>&1 || true
fi
print -u2 -r -- "The new app did not remain running; the previous version was restored."
exit 1
