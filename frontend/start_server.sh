#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

if ! command -v npm >/dev/null 2>&1; then
  echo "npm is required to run the frontend server." >&2
  exit 1
fi

npm install
npm run dev -- --hostname 0.0.0.0 --port "${PORT:-3000}"
