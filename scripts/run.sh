#!/usr/bin/env bash
set -euo pipefail

APP_NAME="NPYViewer"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true
APP_BUNDLE="$("$ROOT_DIR/scripts/build.sh")"
/usr/bin/open -n "$APP_BUNDLE"
