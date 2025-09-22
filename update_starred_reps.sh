#!/usr/bin/env zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
UPDATE_SCRIPT="${SCRIPT_DIR}/update_summary.sh"

usage() {
  cat <<'USAGE' >&2
Usage: update_starred_reps.sh [--dry-run] [-t <range>] [-h]
  --dry-run    Print the repositories and commands without executing update_summary.sh.
  -t <range>   Time window for repo updates (default: 1w). Format: <number><unit>
               Units: d (days), w (weeks), m (months e.g. 30 days).
               Examples: 3d, 1w, 2m
  -h           Show this help.

Requires: curl, python3, and a GitHub token in $GITHUB_PERSONAL_ACCESS_TOKEN with read:user & public_repo scopes.
USAGE
}

validate_update_script() {
  if [[ ! -x "$UPDATE_SCRIPT" ]]; then
    if [[ -f "$UPDATE_SCRIPT" ]]; then
      chmod +x "$UPDATE_SCRIPT"
    else
      printf 'Error: update_summary.sh not found at %s\n' "$UPDATE_SCRIPT" >&2
      exit 1
    fi
  fi
}

parse_range() {
  local input="$1"
  if [[ ! $input =~ ^([0-9]+)([dwm])$ ]]; then
    printf 'Error: invalid range "%s". Use e.g. 3d, 1w, 2m.\n' "$input" >&2
    exit 1
  fi
  local amount=${match[1]}
  local unit=${match[2]}

  python3 - "$amount" "$unit" <<'PY'
import sys
from datetime import datetime, timedelta, timezone

amount = int(sys.argv[1])
unit = sys.argv[2]

if unit == 'd':
    delta = timedelta(days=amount)
elif unit == 'w':
    delta = timedelta(weeks=amount)
elif unit == 'm':
    delta = timedelta(days=30 * amount)
else:
    raise SystemExit('unsupported unit')

cutoff = datetime.now(timezone.utc) - delta
print(cutoff.isoformat())
PY
}

fetch_starred() {
  local page=1
  local cutoff_iso="$1"
  local per_page=100
  local -a repos=()

  while true; do
    local response
    if ! response=$(curl -sS -w '\n%{http_code}' -H "Accept: application/vnd.github+json" \
      -H "Authorization: token ${GITHUB_PERSONAL_ACCESS_TOKEN}" \
      "https://api.github.com/user/starred?per_page=${per_page}&page=${page}"); then
      printf 'Error: failed to contact GitHub API on page %d.\n' "$page" >&2
      exit 1
    fi

    local status_line
    status_line=$(printf '%s\n' "$response" | tail -n1 | tr -d '\r')

    local body
    body=$(printf '%s\n' "$response" | sed '$d')

    if [[ -z $status_line ]]; then
      printf 'Error: Missing status line from GitHub API response on page %d.\n' "$page" >&2
      exit 1
    fi

    if [[ ! $status_line =~ ^[0-9]{3}$ ]]; then
      printf 'Error: Unexpected status value "%s" from GitHub API on page %d.\n' "$status_line" "$page" >&2
      exit 1
    fi

    if [[ -z $body ]]; then
      printf 'Error: Unexpected empty response from GitHub API on page %d.\n' "$page" >&2
      exit 1
    fi

    if [[ $status_line == 401 || $status_line == 403 ]]; then
      printf 'Error: GitHub API returned status %s. Check token scopes and rate limits.\n' "$status_line" >&2
      exit 1
    elif (( status_line >= 400 )); then
      printf 'Error: GitHub API returned status %s with body: %s\n' "$status_line" "$body" >&2
      exit 1
    fi

    local output
    output=$(
      STARRED_RESPONSE="$body" python3 - "$cutoff_iso" <<'PY'
import json
import os
import sys
from datetime import datetime, timezone

cutoff_iso = sys.argv[1]
cutoff = datetime.fromisoformat(cutoff_iso)

raw = os.environ.get('STARRED_RESPONSE', '')
if not raw:
    print("__ERROR__Empty response body")
    sys.exit(0)

try:
    data = json.loads(raw)
except json.JSONDecodeError as exc:
    print(f"__ERROR__Unable to decode JSON: {exc}")
    sys.exit(0)

if isinstance(data, dict) and data.get('message'):
    print(f"__ERROR__GitHub API error: {data.get('message')}")
    sys.exit(0)

if not isinstance(data, list):
    print("__ERROR__Unexpected response shape")
    sys.exit(0)

selected = []
for repo in data:
    ts = repo.get('pushed_at') or repo.get('updated_at')
    if not ts:
        continue
    try:
        dt = datetime.fromisoformat(ts.replace('Z', '+00:00'))
    except ValueError:
        continue
    if dt >= cutoff:
        owner = repo.get('owner', {}).get('login')
        name = repo.get('name')
        if owner and name:
            selected.append(f"{owner}/{name}")

for repo in selected:
    print(repo)

print(f"__COUNT__{len(data)}")
PY
    )

    if [[ $output == __ERROR__* ]]; then
      printf 'Error: %s\n' "${output#__ERROR__}" >&2
      exit 1
    fi

    local count_line=${output##*$'\n'}
    if [[ $count_line != __COUNT__* ]]; then
      printf 'Error: Unexpected parser output on page %d\n' "$page" >&2
      exit 1
    fi

    local page_count=${count_line#__COUNT__}
    local selected_lines
    selected_lines=$(printf '%s' "$output" | sed '$d')

    if [[ -n $selected_lines ]]; then
      while IFS= read -r repo; do
        [[ -z $repo ]] && continue
        repos+=("$repo")
      done <<< "$selected_lines"
    fi

    if (( page_count < per_page )); then
      break
    fi

    ((page++))
  done

  printf '%s\n' "${repos[@]}"
}

main() {
  local range="1w"
  local dry_run=false

  while [[ $# -gt 0 ]]; do
    case $1 in
      --dry-run)
        dry_run=true
        shift
        ;;
      -t)
        if [[ $# -lt 2 ]]; then
          printf 'Error: -t requires an argument.\n' >&2
          usage
          exit 1
        fi
        range="$2"
        shift 2
        ;;
      -h)
        usage
        exit 0
        ;;
      --)
        shift
        break
        ;;
      -*)
        printf 'Error: unknown option %s\n' "$1" >&2
        usage
        exit 1
        ;;
      *)
        printf 'Error: unexpected argument %s\n' "$1" >&2
        usage
        exit 1
        ;;
    esac
  done

  if [[ -z ${GITHUB_PERSONAL_ACCESS_TOKEN:-} ]]; then
    printf 'Error: GITHUB_PERSONAL_ACCESS_TOKEN environment variable not set.\n' >&2
    exit 1
  fi

  validate_update_script

  local cutoff_iso
  cutoff_iso=$(parse_range "$range")

  local -a repos=()
  while IFS= read -r repo; do
    [[ -z $repo ]] && continue
    repos+=("$repo")
  done < <(fetch_starred "$cutoff_iso")

  if (( ${#repos[@]} == 0 )); then
    printf 'No starred repositories updated since %s.\n' "$cutoff_iso" >&2
    exit 0
  fi

  if $dry_run; then
    printf 'Processing %d repositories updated since %s (dry run)...\n' "${#repos[@]}" "$cutoff_iso"
  else
    printf 'Processing %d repositories updated since %s...\n' "${#repos[@]}" "$cutoff_iso"
  fi

  for full_name in "${repos[@]}"; do
    local owner=${full_name%%/*}
    local name=${full_name#*/}
    printf 'Updating %s...\n' "$full_name"
    if $dry_run; then
      printf '[DRY-RUN] %s "%s" "%s"\n' "$UPDATE_SCRIPT" "$owner" "$name"
    else
      "$UPDATE_SCRIPT" "$owner" "$name"
    fi
  done
}

main "$@"
