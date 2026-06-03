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

if [ "${REMOTE_LIBVIRT_ENABLED:-false}" = "true" ]; then
  echo "Remote libvirt workers enabled; provisioning local and remote VMs."
fi

vagrant up --no-parallel
