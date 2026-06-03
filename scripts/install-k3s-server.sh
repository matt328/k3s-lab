#!/usr/bin/env bash
# Install k3s in server mode with bundled Traefik disabled (Traefik is
# GitOps-managed) and install the Gateway API standard CRDs.
#
# Required env: K3S_TOKEN, NODE_IP, GATEWAY_API_VERSION
#
# Note: k3s server args are baked in at install time. Changing
# INSTALL_K3S_EXEC after k3s is already installed will not take effect.
# To change them you must `vagrant destroy && vagrant up`.
set -euo pipefail

: "${K3S_TOKEN:?}"
: "${NODE_IP:?}"
: "${GATEWAY_API_VERSION:?}"

if ! [ -x /usr/local/bin/k3s ]; then
  # Write a config file so the chosen flags persist and are visible.
  install -d -m 0755 /etc/rancher/k3s
  cat >/etc/rancher/k3s/config.yaml <<EOF
# Managed by scripts/install-k3s-server.sh. Edit and re-install to change.
disable:
  - traefik
node-ip: ${NODE_IP}
write-kubeconfig-mode: "0644"
EOF

  curl -sfL https://get.k3s.io | \
    K3S_TOKEN="${K3S_TOKEN}" \
    sh -

  systemctl enable --now k3s
else
  echo "k3s already installed; skipping install (config changes require a destroy+up)"
fi

# Wait for the API server to be ready before applying CRDs.
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
for i in $(seq 1 60); do
  if /usr/local/bin/kubectl get --raw='/readyz' >/dev/null 2>&1; then
    break
  fi
  echo "waiting for k3s API to be ready ($i/60)..."
  sleep 2
done

# Install Gateway API standard CRDs. Idempotent (kubectl apply).
# Pinned via GATEWAY_API_VERSION so all clusters agree.
echo "applying Gateway API CRDs ${GATEWAY_API_VERSION}"
/usr/local/bin/kubectl apply -f \
  "https://github.com/kubernetes-sigs/gateway-api/releases/download/${GATEWAY_API_VERSION}/standard-install.yaml"
