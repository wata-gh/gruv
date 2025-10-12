#!/usr/bin/env zsh
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: update_summary.sh <organization> <repository>" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
NODE_HELPER="${SCRIPT_DIR}/scripts/generate_summary.mjs"
SDK_DIR="${SCRIPT_DIR}/node_modules/@openai/codex-sdk"

if [[ ! -f "$NODE_HELPER" ]]; then
  echo "Error: helper script not found at ${NODE_HELPER}" >&2
  exit 1
fi

if [[ ! -d "$SDK_DIR" ]]; then
  echo "Error: @openai/codex-sdk is not installed. Run 'npm install @openai/codex-sdk' in ${SCRIPT_DIR}." >&2
  exit 1
fi

node "$NODE_HELPER" "$1" "$2"
