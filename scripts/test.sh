#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHADER_BUILD_DIR="$ROOT_DIR/.build/npyviewer-shaders"
METALLIB_PATH="$SHADER_BUILD_DIR/default.metallib"

cd "$ROOT_DIR"
MIN_SYSTEM_VERSION="${MIN_SYSTEM_VERSION:-11.0}" "$ROOT_DIR/scripts/compile_shaders.sh" "$METALLIB_PATH"
NPYVIEWER_METALLIB_PATH="$METALLIB_PATH" swift test "$@"
