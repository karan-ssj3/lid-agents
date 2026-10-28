#!/bin/bash
# One-time, for maintainers: store the Developer ID certificate and the App Store Connect API
# key as GitHub Actions secrets, so CI can sign and notarize every release.
# Run it in a terminal (it asks for passwords): scripts/setup-signing-secrets.sh
#
# Secrets it sets: MACOS_CERT_P12, MACOS_CERT_PASSWORD, NOTARY_KEY_P8, NOTARY_KEY_ID, NOTARY_ISSUER_ID
# It also saves a local `notarytool` profile named lid-agents for local notarized builds.
set -euo pipefail

REPO="liam-machine/lid-agents"
bold() { printf '\n\033[1m%s\033[0m\n' "$*"; }

command -v gh >/dev/null || { echo "Needs the GitHub CLI (gh), logged in."; exit 1; }

bold "1/3  Developer ID certificate"
echo "In Keychain Access: login → My Certificates → right-click"
echo "\"Developer ID Application: …\" → Export… → save as a .p12 and choose a password."
read -r -p "Path to the .p12 (drag the file here): " p12
p12="${p12//\\ / }"; p12="${p12%\"}"; p12="${p12#\"}"; p12="${p12% }"
[ -f "$p12" ] || { echo "No file at $p12"; exit 1; }
read -r -s -p "The password you gave it: " p12pw; echo
openssl pkcs12 -in "$p12" -passin "pass:$p12pw" -nokeys -legacy >/dev/null 2>&1 \
  || openssl pkcs12 -in "$p12" -passin "pass:$p12pw" -nokeys >/dev/null 2>&1 \
  || { echo "That password doesn't open the .p12."; exit 1; }
echo "Certificate opens. ✓"

bold "2/3  App Store Connect API key (for notarization)"
default_key="$(ls ~/.appstoreconnect/private_keys/AuthKey_*.p8 2>/dev/null | head -1 || true)"
read -r -p "Path to the AuthKey_XXXX.p8 [${default_key:-none found}]: " key
key="${key:-$default_key}"; key="${key//\\ / }"
[ -f "$key" ] || { echo "No file at $key"; exit 1; }
key_id="$(basename "$key" .p8)"; key_id="${key_id#AuthKey_}"
echo "Key ID: $key_id"
echo "The Issuer ID is in App Store Connect → Users and Access → Integrations → App Store Connect API (above the keys list)."
read -r -p "Issuer ID: " issuer
echo "Checking the key with Apple…"
xcrun notarytool history --key "$key" --key-id "$key_id" --issuer "$issuer" >/dev/null \
  || { echo "Apple rejected that key / Issuer ID."; exit 1; }
echo "Apple accepts the key. ✓"

bold "3/3  Saving to GitHub ($REPO) and this Mac"
base64 -i "$p12" | gh secret set MACOS_CERT_P12 -R "$REPO"
printf '%s' "$p12pw" | gh secret set MACOS_CERT_PASSWORD -R "$REPO"
gh secret set NOTARY_KEY_P8 -R "$REPO" < "$key"
printf '%s' "$key_id" | gh secret set NOTARY_KEY_ID -R "$REPO"
printf '%s' "$issuer" | gh secret set NOTARY_ISSUER_ID -R "$REPO"
xcrun notarytool store-credentials lid-agents --key "$key" --key-id "$key_id" --issuer "$issuer" >/dev/null
echo "GitHub secrets set, and local notarytool profile \"lid-agents\" saved."

bold "Done."
echo "You can delete the exported .p12 now: rm \"$p12\""
