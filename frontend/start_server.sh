#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

usage() {
  cat <<'USAGE'
Usage: ./start_server.sh [--prod]

Options:
  --prod       Build and serve the pre-rendered static bundle (next build + npx serve).
  -h, --help   Show this help message.
USAGE
}

MODE="dev"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --prod|--production)
      MODE="prod"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if ! command -v npm >/dev/null 2>&1; then
  echo "npm is required to run the frontend server." >&2
  exit 1
fi

npm install

HOST="${HOST:-0.0.0.0}"
PORT="${PORT:-3000}"
EXTRA_ARGS=("--hostname" "$HOST" "--port" "$PORT")

if [[ "$MODE" == "prod" ]]; then
  npm run build
  npm run preview -- --listen "tcp://${HOST}:${PORT}"
else
  npm run dev -- "${EXTRA_ARGS[@]}"
fi
