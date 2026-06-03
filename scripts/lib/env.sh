#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

load_env_file() {
  local file="$1"
  if [ -f "$file" ]; then
    set -a
    # shellcheck disable=SC1090
    source "$file"
    set +a
  fi
}

load_env_file "${repo_root}/.env.example"
load_env_file "${repo_root}/.env.local"

require_env() {
  local name="$1"
  local value="${!name:-}"
  if [ -z "$value" ] || [[ "$value" == replace-me* ]] || [[ "$value" == YOUR_* ]]; then
    echo "error: ${name} is not set. Copy .env.example to .env.local and fill it in." >&2
    exit 1
  fi
}
