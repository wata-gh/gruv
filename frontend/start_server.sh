#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

usage() {
  cat <<'USAGE'
Usage: ./start_server.sh [--prod]

Options:
  --prod       Build and start the Next.js app in production mode (next build/start).
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
  npm run start -- "${EXTRA_ARGS[@]}"
else
  npm run dev -- "${EXTRA_ARGS[@]}"
fi
