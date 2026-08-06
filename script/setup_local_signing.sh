#!/bin/zsh
set -euo pipefail

readonly IDENTITY_NAME="Neon Notch Local Code Signing"
readonly LOGIN_KEYCHAIN="${HOME}/Library/Keychains/login.keychain-db"

openssl_pkcs12_supports_legacy() {
  local help_output
  help_output="$(openssl pkcs12 -help 2>&1 || true)"
  [[ "${help_output}" == *"-legacy"* ]]
}

if security find-identity -v -p codesigning "${LOGIN_KEYCHAIN}" | grep -Fq "${IDENTITY_NAME}"; then
  print -r -- "Certificate already available: ${IDENTITY_NAME}"
  exit 0
fi

readonly TEMP_DIRECTORY="$(mktemp -d "${TMPDIR:-/tmp}/neon-notch-signing.XXXXXX")"
trap 'rm -rf -- "${TEMP_DIRECTORY}"' EXIT

readonly CERTIFICATE_PATH="${TEMP_DIRECTORY}/neon-notch-code-signing.cer"
readonly PRIVATE_KEY_PATH="${TEMP_DIRECTORY}/neon-notch-code-signing.key"
readonly ARCHIVE_PATH="${TEMP_DIRECTORY}/neon-notch-code-signing.p12"
readonly ARCHIVE_PASSWORD="$(openssl rand -hex 24)"
typeset -a pkcs12_compatibility_options=()

if openssl_pkcs12_supports_legacy; then
  pkcs12_compatibility_options=(-legacy)
fi

openssl req \
  -newkey rsa:3072 \
  -nodes \
  -x509 \
  -sha256 \
  -days 3650 \
  -subj "/CN=${IDENTITY_NAME}/O=Neon Notch Local/OU=Personal Development" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=codeSigning" \
  -keyout "${PRIVATE_KEY_PATH}" \
  -out "${CERTIFICATE_PATH}"

openssl pkcs12 \
  -export \
  "${pkcs12_compatibility_options[@]}" \
  -name "${IDENTITY_NAME}" \
  -inkey "${PRIVATE_KEY_PATH}" \
  -in "${CERTIFICATE_PATH}" \
  -out "${ARCHIVE_PATH}" \
  -passout "pass:${ARCHIVE_PASSWORD}"

security import "${ARCHIVE_PATH}" \
  -k "${LOGIN_KEYCHAIN}" \
  -P "${ARCHIVE_PASSWORD}" \
  -T /usr/bin/codesign \
  -T /usr/bin/security >/dev/null

security add-trusted-cert \
  -d \
  -r trustRoot \
  -k "${LOGIN_KEYCHAIN}" \
  "${CERTIFICATE_PATH}"

if ! security find-identity -v -p codesigning "${LOGIN_KEYCHAIN}" | grep -Fq "${IDENTITY_NAME}"; then
  print -u2 -r -- "The certificate was imported but is not a valid code-signing identity."
  print -u2 -r -- "Open Keychain Access, verify its trust settings, and run this command again."
  exit 1
fi

print -r -- "Created ${IDENTITY_NAME}; it is valid for ten years and restricted to code signing."
