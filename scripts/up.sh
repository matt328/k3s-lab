#!/usr/bin/env bash
# Bring the lab up deterministically.
#
# Plain `vagrant up` may provision machines in parallel. That can race agents
# ahead of their masters, causing the agent join script to wait on a server that
# has not installed k3s yet. `--no-parallel` preserves the machine order in the
# Vagrantfile: each master is provisioned before its agent.
set -euo pipefail

cd "$(dirname "$0")/.."

set -a
# shellcheck disable=SC1091
[ -f .env.example ] && . ./.env.example
# shellcheck disable=SC1091
[ -f .env.local ] && . ./.env.local
set +a

enabled_profiles=()
[ "${LOCAL_AGENTS_ENABLED:-false}" = "true" ] && enabled_profiles+=("local agents")
[ "${REMOTE_LIBVIRT_ENABLED:-false}" = "true" ] && enabled_profiles+=("cluster-A remote agents")
[ "${CITADEL_LIBVIRT_ENABLED:-false}" = "true" ] && enabled_profiles+=("citadel cluster-B agents")

if [ "${#enabled_profiles[@]}" -gt 0 ]; then
  joined="$(printf '%s, ' "${enabled_profiles[@]}")"
  printf 'Provisioning local masters plus: %s\n' "${joined%, }"
else
  echo "Provisioning local masters only."
fi

vagrant up --no-parallel
