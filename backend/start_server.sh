#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

if command -v mise >/dev/null 2>&1; then
  ruby_version=$(mise current ruby 2>/dev/null || true)
  if [[ -n "$ruby_version" ]]; then
    exec mise exec ruby@"$ruby_version" -- ruby server.rb
  fi
fi

if command -v ruby >/dev/null 2>&1; then
  exec ruby server.rb
fi

echo "Ruby is required to run the backend server." >&2
exit 1
