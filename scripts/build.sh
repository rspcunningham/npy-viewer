#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

SIGNING_MODE="${SIGNING_MODE:-development}" "$ROOT_DIR/scripts/stage_app.sh"
