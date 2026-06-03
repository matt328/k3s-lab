#!/usr/bin/env bash
# Bring the lab up deterministically.
#
# Plain `vagrant up` may provision machines in parallel. That can race agents
# ahead of their masters, causing the agent join script to wait on a server that
# has not installed k3s yet. `--no-parallel` preserves the machine order in the
# Vagrantfile: each master is provisioned before its agent.
set -euo pipefail

cd "$(dirname "$0")/.."

vagrant up --no-parallel
