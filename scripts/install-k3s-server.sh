#!/usr/bin/env bash
# Install k3s in server mode with bundled Traefik and ServiceLB disabled
# (both are GitOps-managed) and install the Gateway API standard CRDs.
#
# Required env: K3S_TOKEN, NODE_IP, GATEWAY_API_VERSION
#
# Server config is reconciled on every provision run. If it changes after k3s is
# already installed, the service is restarted so the new config is applied.
set -euo pipefail

: "${K3S_TOKEN:?}"
: "${NODE_IP:?}"
: "${GATEWAY_API_VERSION:?}"

install -d -m 0755 /etc/rancher/k3s
desired_config="$(mktemp)"
cat >"${desired_config}" <<EOF
# Managed by scripts/install-k3s-server.sh. Edit and re-install to change.
disable:
  - traefik
  - servicelb
node-ip: ${NODE_IP}
write-kubeconfig-mode: "0644"
EOF

config_changed=false
if ! cmp -s "${desired_config}" /etc/rancher/k3s/config.yaml 2>/dev/null; then
  install -m 0644 "${desired_config}" /etc/rancher/k3s/config.yaml
  config_changed=true
fi
rm -f "${desired_config}"

if ! [ -x /usr/local/bin/k3s ]; then
  curl -sfL https://get.k3s.io | \
    K3S_TOKEN="${K3S_TOKEN}" \
    sh -

  systemctl enable --now k3s
else
  echo "k3s already installed; skipping install"
  if [ "${config_changed}" = true ]; then
    echo "k3s config changed; restarting k3s"
    systemctl restart k3s
  fi
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
