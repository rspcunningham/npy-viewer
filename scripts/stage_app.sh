#!/usr/bin/env bash
set -euo pipefail

APP_NAME="NPYViewer"
BUNDLE_ID="com.parasight.NPYViewer"
MIN_SYSTEM_VERSION="15.0"
APP_VERSION="${APP_VERSION:-0.0.1}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
SIGNING_MODE="${SIGNING_MODE:-development}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"

find_identity() {
  local pattern="$1"
  security find-identity -v -p codesigning 2>/dev/null | awk -F'"' -v pat="$pattern" '$0 ~ pat { print $2; exit }'
}

resolve_signing_identity() {
  case "$SIGNING_MODE" in
    developer-id)
      if [[ -n "${DEVELOPER_ID_IDENTITY:-}" ]]; then
        printf '%s\n' "$DEVELOPER_ID_IDENTITY"
      else
        find_identity 'Developer ID Application'
      fi
      ;;
    development)
      if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
        printf '%s\n' "$CODESIGN_IDENTITY"
      else
        find_identity 'Apple Development'
      fi
      ;;
    ad-hoc)
      printf '%s\n' "-"
      ;;
    *)
      echo "Unknown SIGNING_MODE '$SIGNING_MODE'. Use development, developer-id, or ad-hoc." >&2
      exit 2
      ;;
  esac
}

write_info_plist() {
  cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleDocumentTypes</key>
  <array>
    <dict>
      <key>CFBundleTypeExtensions</key>
      <array>
        <string>npy</string>
      </array>
      <key>CFBundleTypeIconFile</key>
      <string>AppIcon</string>
      <key>CFBundleTypeName</key>
      <string>NumPy Array</string>
      <key>CFBundleTypeRole</key>
      <string>Viewer</string>
      <key>LSHandlerRank</key>
      <string>Owner</string>
      <key>LSItemContentTypes</key>
      <array>
        <string>com.numpy.npy</string>
      </array>
    </dict>
  </array>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$APP_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_NUMBER</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>UTImportedTypeDeclarations</key>
  <array>
    <dict>
      <key>UTTypeConformsTo</key>
      <array>
        <string>public.data</string>
      </array>
      <key>UTTypeDescription</key>
      <string>NumPy Array</string>
      <key>UTTypeIdentifier</key>
      <string>com.numpy.npy</string>
      <key>UTTypeTagSpecification</key>
      <dict>
        <key>public.filename-extension</key>
        <array>
          <string>npy</string>
        </array>
      </dict>
    </dict>
  </array>
</dict>
</plist>
PLIST
}

sign_app() {
  local identity="$1"

  if [[ "$SIGNING_MODE" == "developer-id" && -z "$identity" ]]; then
    cat >&2 <<'EOF'
Developer ID signing requested, but no "Developer ID Application" identity was found.

Install a Developer ID Application certificate for your Apple Developer team, or set:
  DEVELOPER_ID_IDENTITY="Developer ID Application: Your Name (TEAMID)"
EOF
    exit 1
  fi

  if [[ -z "$identity" ]]; then
    identity="-"
  fi

  if [[ "$identity" == "-" ]]; then
    codesign --force --sign - "$APP_BINARY"
    codesign --force --sign - "$APP_BUNDLE"
  elif [[ "$SIGNING_MODE" == "developer-id" ]]; then
    codesign --force --options runtime --timestamp --sign "$identity" "$APP_BINARY"
    codesign --force --options runtime --timestamp --sign "$identity" "$APP_BUNDLE"
  else
    codesign --force --options runtime --sign "$identity" "$APP_BINARY"
    codesign --force --options runtime --sign "$identity" "$APP_BUNDLE"
  fi
}

cd "$ROOT_DIR"
swift build -c release --product "$APP_NAME" >&2
BUILD_BINARY="$(swift build -c release --show-bin-path)/$APP_NAME"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
cp "$ROOT_DIR/resources/AppIcon.icns" "$APP_RESOURCES/AppIcon.icns"
chmod +x "$APP_BINARY"
write_info_plist
sign_app "$(resolve_signing_identity)"

/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
  -f "$APP_BUNDLE" >/dev/null 2>&1 || true

printf '%s\n' "$APP_BUNDLE"
