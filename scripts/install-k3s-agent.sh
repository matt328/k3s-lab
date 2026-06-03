#!/usr/bin/env bash
# Install k3s in agent mode joining its cluster's master.
#
# Required env: K3S_TOKEN, MASTER_IP, NODE_IP
# Optional env: NODE_LABELS (comma-separated k3s node labels), FLANNEL_IFACE
# (default: eth1)
set -euo pipefail

: "${K3S_TOKEN:?}"
: "${MASTER_IP:?}"
: "${NODE_IP:?}"
FLANNEL_IFACE="${FLANNEL_IFACE:-eth1}"

# Persist node-ip via a config file so it survives reinstalls / restarts.
install -d -m 0755 /etc/rancher/k3s
desired_config="$(mktemp)"
cat >"${desired_config}" <<EOF
# Managed by scripts/install-k3s-agent.sh. Edit and re-install to change.
flannel-iface: ${FLANNEL_IFACE}
node-ip: ${NODE_IP}
EOF

if [ -n "${NODE_LABELS:-}" ]; then
  {
    echo "node-label:"
    for label in ${NODE_LABELS//,/ }; do
      echo "  - ${label}"
    done
  } >>"${desired_config}"
fi

config_changed=false
if ! cmp -s "${desired_config}" /etc/rancher/k3s/config.yaml 2>/dev/null; then
  install -m 0644 "${desired_config}" /etc/rancher/k3s/config.yaml
  config_changed=true
fi
rm -f "${desired_config}"

if [ -x /usr/local/bin/k3s ]; then
  echo "k3s already installed; skipping install"
  if [ "${config_changed}" = true ]; then
    echo "k3s agent config changed; restarting k3s-agent"
    systemctl restart k3s-agent
  fi
  exit 0
fi

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
