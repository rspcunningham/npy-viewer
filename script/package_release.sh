#!/usr/bin/env bash
set -euo pipefail

APP_NAME="NPYViewer"
VERSION="${APP_VERSION:-0.0.1}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RELEASE_DIR="$ROOT_DIR/dist/release"
NOTARY_ZIP="$RELEASE_DIR/$APP_NAME-$VERSION-notary.zip"
FINAL_ZIP="$RELEASE_DIR/$APP_NAME-$VERSION-macOS-arm64.zip"
NOTARY_PROFILE="${NOTARY_PROFILE:-NPYViewerNotaryProfile}"

cd "$ROOT_DIR"
mkdir -p "$RELEASE_DIR"

APP_BUNDLE="$(SIGNING_MODE=developer-id "$ROOT_DIR/script/stage_app.sh")"

codesign --verify --strict --verbose=2 "$APP_BUNDLE"
codesign --verify --strict --verbose=2 "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

rm -f "$NOTARY_ZIP" "$FINAL_ZIP"
ditto -c -k --keepParent "$APP_BUNDLE" "$NOTARY_ZIP"

if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
  cat >&2 <<EOF
No usable notarytool keychain profile named "$NOTARY_PROFILE" was found.

Create it once with:
  xcrun notarytool store-credentials "$NOTARY_PROFILE"

Then rerun:
  NOTARY_PROFILE="$NOTARY_PROFILE" ./script/package_release.sh
EOF
  exit 1
fi

xcrun notarytool submit "$NOTARY_ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$APP_BUNDLE"
xcrun stapler validate "$APP_BUNDLE"
spctl -a -t exec -vv "$APP_BUNDLE"

ditto -c -k --keepParent "$APP_BUNDLE" "$FINAL_ZIP"
printf '%s\n' "$FINAL_ZIP"
