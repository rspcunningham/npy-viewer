#!/usr/bin/env bash
set -euo pipefail

APP_NAME="NPYViewer"
REPO="${NPYVIEWER_REPO:-rspcunningham/npy-viewer}"
ASSET_SUFFIX="macOS-arm64.zip"
DEFAULT_INSTALL_DIR="/Applications"

fail() {
  printf 'error: %s\n' "$1" >&2
  exit 1
}

need_command() {
  command -v "$1" >/dev/null 2>&1 || fail "missing required command: $1"
}

[[ "$(uname -s)" == "Darwin" ]] || fail "$APP_NAME is a macOS app"
[[ "$(uname -m)" == "arm64" ]] || fail "$APP_NAME releases are built for Apple Silicon Macs"

need_command codesign
need_command curl
need_command ditto
need_command shasum
need_command spctl

if [[ -n "${INSTALL_DIR:-}" ]]; then
  install_dir="$INSTALL_DIR"
elif [[ -w "$DEFAULT_INSTALL_DIR" ]]; then
  install_dir="$DEFAULT_INSTALL_DIR"
else
  install_dir="$HOME/Applications"
fi

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/npyviewer-install.XXXXXX")"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

release_base="https://github.com/$REPO/releases/latest/download"
checksum_path="$tmp_dir/SHA256SUMS.txt"
zip_path="$tmp_dir/$APP_NAME.zip"
extract_dir="$tmp_dir/extract"

mkdir -p "$extract_dir" "$install_dir"

printf 'Resolving latest %s release...\n' "$APP_NAME"
curl -fsSL "$release_base/SHA256SUMS.txt" -o "$checksum_path"

asset_name="$(
  awk -v suffix="$ASSET_SUFFIX" '$2 ~ suffix "$" { print $2; exit }' "$checksum_path"
)"
[[ -n "$asset_name" ]] || fail "latest release does not include a $ASSET_SUFFIX asset"

expected_sha="$(
  awk -v file="$asset_name" '$2 == file { print $1; exit }' "$checksum_path"
)"
[[ -n "$expected_sha" ]] || fail "latest release does not include a checksum for $asset_name"

printf 'Downloading %s...\n' "$asset_name"
curl -fL "$release_base/$asset_name" -o "$zip_path"

actual_sha="$(shasum -a 256 "$zip_path" | awk '{ print $1 }')"
[[ "$actual_sha" == "$expected_sha" ]] || fail "checksum mismatch for $asset_name"

printf 'Extracting...\n'
ditto -x -k "$zip_path" "$extract_dir"

source_app="$extract_dir/$APP_NAME.app"
[[ -d "$source_app" ]] || fail "downloaded archive did not contain $APP_NAME.app"

printf 'Verifying signature and notarization...\n'
codesign --verify --strict --verbose=2 "$source_app" >/dev/null
spctl -a -t exec -vv "$source_app" >/dev/null

target_app="$install_dir/$APP_NAME.app"
printf 'Installing to %s...\n' "$target_app"
pkill -x "$APP_NAME" >/dev/null 2>&1 || true
rm -rf "$target_app"
ditto "$source_app" "$target_app"

/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
  -f "$target_app" >/dev/null 2>&1 || true

printf '\nInstalled %s at:\n  %s\n' "$APP_NAME" "$target_app"
