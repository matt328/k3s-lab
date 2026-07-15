#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/env.sh
source "${repo_root}/scripts/lib/env.sh"

registry_host="${LAB_OCI_REGISTRY_HOST:?}"
registry_ip="${LAB_OCI_REGISTRY_IP:-${CLUSTER_B_INGRESS_IP:?}}"

running_nodes="$(vagrant status --machine-readable | awk -F, '$3 == "state" && $4 == "running" { print $2 }')"

if [ -z "${running_nodes}" ]; then
  echo "error: no running Vagrant nodes found" >&2
  exit 1
fi

failed_nodes=()
for node in ${running_nodes}; do
  echo "configuring ${node} for ${registry_host}"
  if ! vagrant ssh "${node}" -c "sudo LAB_OCI_REGISTRY_HOST='${registry_host}' LAB_OCI_REGISTRY_IP='${registry_ip}' bash -s" <<'REMOTE'
set -euo pipefail

: "${LAB_OCI_REGISTRY_HOST:?}"
: "${LAB_OCI_REGISTRY_IP:?}"

hosts_line="${LAB_OCI_REGISTRY_IP} ${LAB_OCI_REGISTRY_HOST}"
hosts_tmp="$(mktemp)"
awk -v host="${LAB_OCI_REGISTRY_HOST}" '
  $0 ~ "^[[:space:]]*#" { print; next }
  {
    for (i = 2; i <= NF; i++) {
      if ($i == host) {
        next
      }
    }
    print
  }
' /etc/hosts >"${hosts_tmp}"
printf '%s\n' "${hosts_line}" >>"${hosts_tmp}"
install -m 0644 "${hosts_tmp}" /etc/hosts
rm -f "${hosts_tmp}"

install -d -m 0755 /etc/rancher/k3s
desired_registries="$(mktemp)"
cat >"${desired_registries}" <<EOF
# Managed by scripts/configure-oci-registry-nodes.sh.
mirrors:
  "${LAB_OCI_REGISTRY_HOST}":
    endpoint:
      - "http://${LAB_OCI_REGISTRY_HOST}"
EOF

if cmp -s "${desired_registries}" /etc/rancher/k3s/registries.yaml 2>/dev/null; then
  rm -f "${desired_registries}"
  echo "registries.yaml already current"
  exit 0
fi

install -m 0644 "${desired_registries}" /etc/rancher/k3s/registries.yaml
rm -f "${desired_registries}"

if systemctl is-active --quiet k3s-agent; then
  systemctl restart k3s-agent
elif systemctl is-active --quiet k3s; then
  systemctl restart k3s
else
  echo "warning: neither k3s-agent nor k3s is active yet" >&2
fi
REMOTE
  then
    failed_nodes+=("${node}")
  fi
done

if [ "${#failed_nodes[@]}" -gt 0 ]; then
  echo "error: failed to configure: ${failed_nodes[*]}" >&2
  exit 1
fi
