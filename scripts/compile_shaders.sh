#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: scripts/compile_shaders.sh OUTPUT_METALLIB" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHADER_SOURCE="$ROOT_DIR/sources/NPYViewer/Shaders.metal"
OUTPUT_METALLIB="$1"
MIN_SYSTEM_VERSION="${MIN_SYSTEM_VERSION:-11.0}"

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/npyviewer-shaders.XXXXXX")"
cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

AIR_FILE="$WORK_DIR/default.air"

mkdir -p "$(dirname "$OUTPUT_METALLIB")"
echo "Compiling Metal shaders to $OUTPUT_METALLIB" >&2
xcrun metal \
  -mmacosx-version-min="$MIN_SYSTEM_VERSION" \
  -c "$SHADER_SOURCE" \
  -o "$AIR_FILE"
xcrun metallib "$AIR_FILE" -o "$OUTPUT_METALLIB"
