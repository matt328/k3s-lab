#!/usr/bin/env bash
# Install k3s in agent mode joining its cluster's master.
#
# Required env: K3S_TOKEN, MASTER_IP, NODE_IP
set -euo pipefail

: "${K3S_TOKEN:?}"
: "${MASTER_IP:?}"
: "${NODE_IP:?}"

if [ -x /usr/local/bin/k3s ]; then
  echo "k3s already installed; skipping"
  exit 0
fi

# Persist node-ip via a config file so it survives reinstalls / restarts.
install -d -m 0755 /etc/rancher/k3s
cat >/etc/rancher/k3s/config.yaml <<EOF
# Managed by scripts/install-k3s-agent.sh. Edit and re-install to change.
node-ip: ${NODE_IP}
EOF

# wait for the master's API to be reachable
master_ready=false
for i in $(seq 1 60); do
  if (echo >/dev/tcp/${MASTER_IP}/6443) >/dev/null 2>&1; then
    master_ready=true
    break
  fi
  echo "waiting for ${MASTER_IP}:6443 ($i/60)..."
  sleep 5
done

if [ "$master_ready" != true ]; then
  echo "master API ${MASTER_IP}:6443 did not become reachable" >&2
  echo "If you ran plain 'vagrant up', retry with './scripts/up.sh' or 'vagrant up --no-parallel'." >&2
  exit 1
fi

curl -sfL https://get.k3s.io | \
  K3S_URL="https://${MASTER_IP}:6443" \
  K3S_TOKEN="${K3S_TOKEN}" \
  sh -

systemctl enable --now k3s-agent
