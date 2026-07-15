#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

load_env_file() {
  local file="$1"
  local line name value
  [ -f "$file" ] || return 0

  while IFS= read -r line || [ -n "$line" ]; do
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [ -n "$line" ] || continue
    [[ "$line" != \#* ]] || continue
    [[ "$line" == *=* ]] || continue

    name="${line%%=*}"
    value="${line#*=}"
    name="${name%"${name##*[![:space:]]}"}"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"

    [[ "$name" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue
    [ -z "${!name+x}" ] || continue

    if [[ "$value" == \"*\" && "$value" == *\" ]]; then
      value="${value:1:${#value}-2}"
    elif [[ "$value" == \'*\' && "$value" == *\' ]]; then
      value="${value:1:${#value}-2}"
    fi

    printf -v "$name" '%s' "$value"
    export "$name"
  done <"$file"
}

load_env_file "${repo_root}/.env.local"
load_env_file "${repo_root}/.env.example"

require_env() {
  local name="$1"
  local value="${!name:-}"
  if [ -z "$value" ] || [[ "$value" == replace-me* ]] || [[ "$value" == YOUR_* ]]; then
    echo "error: ${name} is not set. Copy .env.example to .env.local and fill it in." >&2
    exit 1
  fi
}
