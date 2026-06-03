#!/usr/bin/env bash
# Pull kubeconfigs from each master, rewrite the server URL to the master's
# LAN IP, and merge them into ~/.kube/config (with a backup).
set -euo pipefail

OUT_DIR="$(cd "$(dirname "$0")/.." && pwd)/kubeconfigs"
mkdir -p "$OUT_DIR"

cd "$(dirname "$0")/.."
set -a
# shellcheck disable=SC1091
[ -f .env.example ] && . ./.env.example
# shellcheck disable=SC1091
[ -f .env.local ] && . ./.env.local
set +a

: "${VM_A_MASTER_IP:?}"
: "${VM_B_MASTER_IP:?}"

declare -A MASTERS=(
  ["cluster-a"]="k3s-a-master:${VM_A_MASTER_IP}"
  ["cluster-b"]="k3s-b-master:${VM_B_MASTER_IP}"
)

for cluster in "${!MASTERS[@]}"; do
  IFS=: read -r vm ip <<<"${MASTERS[$cluster]}"
  out="${OUT_DIR}/${cluster}.yaml"
  echo "→ fetching kubeconfig from ${vm} into ${out}"
  vagrant ssh "$vm" -c "sudo cat /etc/rancher/k3s/k3s.yaml" 2>/dev/null \
    | sed "s|127.0.0.1|${ip}|g" \
    | sed "s|default|${cluster}|g" \
    > "$out"
  chmod 600 "$out"
done

KUBE_DIR="${HOME}/.kube"
KUBE_CFG="${KUBE_DIR}/config"
mkdir -p "$KUBE_DIR"

if [ -f "$KUBE_CFG" ]; then
  backup="${KUBE_CFG}.bak.$(date +%s)"
  cp "$KUBE_CFG" "$backup"
  echo "→ backed up existing ${KUBE_CFG} to ${backup}"
  # Newly-fetched kubeconfigs must come FIRST in the merge so that on a
  # name collision (e.g. you destroyed+recreated a cluster and the old
  # cluster-a entry has a stale CA), the new entries win.
  merge_inputs="${OUT_DIR}/cluster-a.yaml:${OUT_DIR}/cluster-b.yaml:${KUBE_CFG}"
else
  merge_inputs="${OUT_DIR}/cluster-a.yaml:${OUT_DIR}/cluster-b.yaml"
fi

echo "→ merging into ${KUBE_CFG}"
KUBECONFIG="$merge_inputs" kubectl config view --flatten > "${KUBE_CFG}.merged"
mv "${KUBE_CFG}.merged" "$KUBE_CFG"
chmod 600 "$KUBE_CFG"

echo
echo "Done. Contexts now available:"
kubectl config get-contexts
echo
echo "Switch with:  kubectl config use-context cluster-a"
