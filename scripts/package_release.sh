#!/usr/bin/env bash
set -euo pipefail

APP_NAME="NPYViewer"
VERSION="${APP_VERSION:-0.0.1}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RELEASE_DIR="$ROOT_DIR/dist/release"
NOTARY_ZIP="$RELEASE_DIR/$APP_NAME-$VERSION-notary.zip"
FINAL_ZIP="$RELEASE_DIR/$APP_NAME-$VERSION-macOS-arm64.zip"
CHECKSUM_FILE="$RELEASE_DIR/SHA256SUMS.txt"
NOTARY_PROFILE="${NOTARY_PROFILE:-NPYViewerNotaryProfile}"
TMP_DIR=""
NOTARY_ARGS=()

cleanup() {
  if [[ -n "$TMP_DIR" ]]; then
    rm -rf "$TMP_DIR"
  fi
}
trap cleanup EXIT

configure_notary_args() {
  if [[ -n "${APPLE_NOTARY_KEY_BASE64:-}" && -n "${APPLE_NOTARY_KEY_ID:-}" ]]; then
    TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/npyviewer-notary.XXXXXX")"
    local key_path="$TMP_DIR/AuthKey_$APPLE_NOTARY_KEY_ID.p8"
    printf '%s' "$APPLE_NOTARY_KEY_BASE64" | base64 --decode >"$key_path"

    NOTARY_ARGS=(--key "$key_path" --key-id "$APPLE_NOTARY_KEY_ID")
    if [[ -n "${APPLE_NOTARY_ISSUER_ID:-}" ]]; then
      NOTARY_ARGS+=(--issuer "$APPLE_NOTARY_ISSUER_ID")
    fi
    return
  fi

  if [[ -n "${APPLE_ID:-}" && -n "${APPLE_TEAM_ID:-}" && -n "${APPLE_APP_SPECIFIC_PASSWORD:-}" ]]; then
    NOTARY_ARGS=(--apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" --password "$APPLE_APP_SPECIFIC_PASSWORD")
    return
  fi

  if xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
    NOTARY_ARGS=(--keychain-profile "$NOTARY_PROFILE")
    return
  fi

  cat >&2 <<EOF
No notarization credentials were found.

For local use, create a notarytool keychain profile:
  xcrun notarytool store-credentials "$NOTARY_PROFILE"

For CI, provide either:
  APPLE_ID
  APPLE_TEAM_ID
  APPLE_APP_SPECIFIC_PASSWORD

Or App Store Connect API key credentials:
  APPLE_NOTARY_KEY_BASE64
  APPLE_NOTARY_KEY_ID
  APPLE_NOTARY_ISSUER_ID
EOF
  exit 1
}

cd "$ROOT_DIR"
mkdir -p "$RELEASE_DIR"

APP_BUNDLE="$(SIGNING_MODE=developer-id "$ROOT_DIR/scripts/stage_app.sh")"

codesign --verify --strict --verbose=2 "$APP_BUNDLE"
codesign --verify --strict --verbose=2 "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

rm -f "$NOTARY_ZIP" "$FINAL_ZIP"
ditto -c -k --keepParent "$APP_BUNDLE" "$NOTARY_ZIP"

configure_notary_args
xcrun notarytool submit "$NOTARY_ZIP" "${NOTARY_ARGS[@]}" --wait
xcrun stapler staple "$APP_BUNDLE"
xcrun stapler validate "$APP_BUNDLE"
spctl -a -t exec -vv "$APP_BUNDLE"

ditto -c -k --keepParent "$APP_BUNDLE" "$FINAL_ZIP"
rm -f "$NOTARY_ZIP"
(cd "$RELEASE_DIR" && shasum -a 256 "$(basename "$FINAL_ZIP")" >"$(basename "$CHECKSUM_FILE")")
printf '%s\n' "$FINAL_ZIP"
