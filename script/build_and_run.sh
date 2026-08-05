#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
DERIVED_DIR="${PROJECT_DIR}/DerivedData"
CONFIGURATION="${CONFIGURATION:-Debug}"

xcodebuild \
  -project "${PROJECT_DIR}/NeonNotch.xcodeproj" \
  -scheme NeonNotch \
  -configuration "${CONFIGURATION}" \
  -derivedDataPath "${DERIVED_DIR}" \
  CODE_SIGNING_ALLOWED=NO \
  build

APP_PATH="${DERIVED_DIR}/Build/Products/${CONFIGURATION}/Neon Notch.app"
HELPER_PATH="${DERIVED_DIR}/Build/Products/${CONFIGURATION}/NeonNotchHook"

mkdir -p "${APP_PATH}/Contents/Helpers"
cp "${HELPER_PATH}" "${APP_PATH}/Contents/Helpers/NeonNotchHook"
chmod +x "${APP_PATH}/Contents/Helpers/NeonNotchHook"

if [[ "${1:-}" != "--build-only" ]]; then
  open "${APP_PATH}"
fi

print -r -- "${APP_PATH}"
