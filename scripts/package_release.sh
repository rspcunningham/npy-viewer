#!/usr/bin/env bash
set -euo pipefail

APP_NAME="NPYViewer"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RELEASE_DIR="$ROOT_DIR/dist/release"
TMP_DIR="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/npyviewer-release.XXXXXX")"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

fail() {
  printf 'error: %s\n' "$1" >&2
  exit 1
}

need_command() {
  command -v "$1" >/dev/null 2>&1 || fail "missing required command: $1"
}

version_from_git() {
  local ref_name="${GITHUB_REF_NAME:-}"

  if [[ -n "${APP_VERSION:-}" ]]; then
    printf '%s\n' "${APP_VERSION#v}"
    return
  fi

  if [[ -n "$ref_name" && "$ref_name" == v* ]]; then
    printf '%s\n' "${ref_name#v}"
    return
  fi

  git -C "$ROOT_DIR" describe --tags --match 'v[0-9]*' --abbrev=0 2>/dev/null | sed 's/^v//' || printf '0.0.0\n'
}

build_number_from_git() {
  if [[ -n "${BUILD_NUMBER:-}" ]]; then
    printf '%s\n' "$BUILD_NUMBER"
    return
  fi

  printf '%s\n' "${GITHUB_RUN_NUMBER:-1}"
}

validate_version() {
  [[ "$1" =~ ^[0-9]+[.][0-9]+[.][0-9]+$ ]] || fail "APP_VERSION must look like 1.2.3"
}

configure_notary_args() {
  if [[ -n "${APPLE_NOTARY_KEY_BASE64:-}" && -n "${APPLE_NOTARY_KEY_ID:-}" && -n "${APPLE_NOTARY_ISSUER_ID:-}" ]]; then
    NOTARY_KEY_PATH="$TMP_DIR/AuthKey_$APPLE_NOTARY_KEY_ID.p8"
    printf '%s' "$APPLE_NOTARY_KEY_BASE64" | base64 --decode >"$NOTARY_KEY_PATH"
    NOTARY_ARGS=(
      --key "$NOTARY_KEY_PATH"
      --key-id "$APPLE_NOTARY_KEY_ID"
      --issuer "$APPLE_NOTARY_ISSUER_ID"
    )
    return
  fi

  if [[ -n "${APPLE_ID:-}" && -n "${APPLE_TEAM_ID:-}" && -n "${APPLE_APP_SPECIFIC_PASSWORD:-}" ]]; then
    NOTARY_ARGS=(
      --apple-id "$APPLE_ID"
      --team-id "$APPLE_TEAM_ID"
      --password "$APPLE_APP_SPECIFIC_PASSWORD"
    )
    return
  fi

  fail "notarization requires either APPLE_ID/APPLE_TEAM_ID/APPLE_APP_SPECIFIC_PASSWORD or APPLE_NOTARY_KEY_BASE64/APPLE_NOTARY_KEY_ID/APPLE_NOTARY_ISSUER_ID"
}

write_output() {
  local name="$1"
  local value="$2"

  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    printf '%s=%s\n' "$name" "$value" >>"$GITHUB_OUTPUT"
  fi
}

need_command codesign
need_command ditto
need_command git
need_command shasum
need_command spctl
need_command xcrun

VERSION="$(version_from_git)"
validate_version "$VERSION"
BUILD_NUMBER="$(build_number_from_git)"
TAG_NAME="${GITHUB_REF_NAME:-v$VERSION}"
if [[ "$TAG_NAME" != v* ]]; then
  TAG_NAME="v$VERSION"
fi

NOTARY_ZIP="$RELEASE_DIR/$APP_NAME-$VERSION-notary.zip"
FINAL_ZIP="$RELEASE_DIR/$APP_NAME-$VERSION-macOS-arm64.zip"
CHECKSUM_FILE="$RELEASE_DIR/SHA256SUMS.txt"

mkdir -p "$RELEASE_DIR"
rm -f "$NOTARY_ZIP" "$FINAL_ZIP" "$CHECKSUM_FILE"

cd "$ROOT_DIR"
APP_BUNDLE="$(APP_VERSION="$VERSION" BUILD_NUMBER="$BUILD_NUMBER" SIGNING_MODE=developer-id "$ROOT_DIR/scripts/stage_app.sh")"

codesign --verify --strict --verbose=2 "$APP_BUNDLE"
codesign --verify --strict --verbose=2 "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

ditto -c -k --keepParent "$APP_BUNDLE" "$NOTARY_ZIP"

configure_notary_args
xcrun notarytool submit "$NOTARY_ZIP" "${NOTARY_ARGS[@]}" --wait
xcrun stapler staple "$APP_BUNDLE"
xcrun stapler validate "$APP_BUNDLE"
spctl -a -t exec -vv "$APP_BUNDLE"

ditto -c -k --keepParent "$APP_BUNDLE" "$FINAL_ZIP"
(
  cd "$RELEASE_DIR"
  shasum -a 256 "$(basename "$FINAL_ZIP")" >"$(basename "$CHECKSUM_FILE")"
)
rm -f "$NOTARY_ZIP"

write_output "version" "$VERSION"
write_output "tag_name" "$TAG_NAME"
write_output "archive" "$FINAL_ZIP"
write_output "checksum" "$CHECKSUM_FILE"

printf '%s\n' "$FINAL_ZIP"
