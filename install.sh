#!/usr/bin/env bash
set -euo pipefail

APP_NAME="NPYViewer"
REPO="rspcunningham/npy-viewer"
ASSET_PATTERN="macOS-arm64.zip"
DEFAULT_INSTALL_DIR="/Applications"

fail() {
  printf 'error: %s\n' "$1" >&2
  exit 1
}

need_command() {
  command -v "$1" >/dev/null 2>&1 || fail "missing required command: $1"
}

if [[ "$(uname -s)" != "Darwin" ]]; then
  fail "NPYViewer is a macOS app; this installer only runs on macOS"
fi

if [[ "$(uname -m)" != "arm64" ]]; then
  fail "this release artifact is built for Apple Silicon Macs (arm64)"
fi

need_command curl
need_command ditto
need_command shasum
need_command codesign
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

api_url="https://api.github.com/repos/$REPO/releases/latest"
metadata="$(
  curl -fsSL \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "$api_url"
)"

tag="$(
  printf '%s\n' "$metadata" |
    awk -F'"' '/"tag_name"[[:space:]]*:/ { print $4; exit }'
)"

asset_url="$(
  printf '%s\n' "$metadata" |
    awk -F'"' -v pattern="$ASSET_PATTERN" '/"browser_download_url"[[:space:]]*:/ && $4 ~ pattern { print $4; exit }'
)"

checksum_url="$(
  printf '%s\n' "$metadata" |
    awk -F'"' '/"browser_download_url"[[:space:]]*:/ && $4 ~ /SHA256SUMS\.txt$/ { print $4; exit }'
)"

if [[ -z "$tag" || -z "$asset_url" || -z "$checksum_url" ]]; then
  fail "could not find a latest $ASSET_PATTERN release asset for $REPO"
fi

zip_path="$tmp_dir/$APP_NAME.zip"
checksum_path="$tmp_dir/SHA256SUMS.txt"
extract_dir="$tmp_dir/extract"
mkdir -p "$extract_dir" "$install_dir"

printf 'Installing latest %s %s...\n' "$APP_NAME" "$tag"
printf 'Downloading archive...\n'
curl -fL "$asset_url" -o "$zip_path"

printf 'Downloading checksum...\n'
curl -fsSL "$checksum_url" -o "$checksum_path"

expected_sha="$(
  awk -v file="$(basename "$asset_url")" '$2 == file { print $1; exit }' "$checksum_path"
)"

if [[ -z "$expected_sha" ]]; then
  fail "could not find checksum for $(basename "$asset_url")"
fi

actual_sha="$(shasum -a 256 "$zip_path" | awk '{ print $1 }')"
if [[ "$actual_sha" != "$expected_sha" ]]; then
  fail "checksum mismatch for $(basename "$asset_url")"
fi

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

printf '\nInstalled %s %s at:\n  %s\n\n' "$APP_NAME" "$tag" "$target_app"
printf 'Open it with:\n  open "%s"\n' "$target_app"
