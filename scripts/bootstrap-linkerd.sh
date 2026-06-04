#!/usr/bin/env bash
# Install Linkerd control plane + multicluster on both lab clusters.
#
# Linkerd identity keys are private material. They are generated under
# .secrets/linkerd/ (gitignored) and passed to Helm at install/upgrade time.
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/env.sh
source "${script_dir}/lib/env.sh"

cluster_a_context="${CLUSTER_A_CONTEXT:-cluster-a}"
cluster_b_context="${CLUSTER_B_CONTEXT:-cluster-b}"
linkerd_version="${LINKERD_VERSION:-stable-2.14.10}"
linkerd_crds_chart_version="${LINKERD_CRDS_CHART_VERSION:-1.8.0}"
linkerd_control_plane_chart_version="${LINKERD_CONTROL_PLANE_CHART_VERSION:-1.16.11}"
linkerd_multicluster_chart_version="${LINKERD_MULTICLUSTER_CHART_VERSION:-30.11.11}"
linkerd_gateway_a_ip="${LINKERD_GATEWAY_A_IP:-192.168.50.241}"
linkerd_gateway_b_ip="${LINKERD_GATEWAY_B_IP:-192.168.50.246}"
secret_dir="${LINKERD_CERT_DIR:-${repo_root}/.secrets/linkerd}"

helm_path="$("${script_dir}/ensure-helm-v3.sh")"
linkerd_path="$("${script_dir}/ensure-linkerd-cli.sh")"
export PATH="${linkerd_path}:${helm_path}:${PATH}"

mkdir -p "${secret_dir}"
chmod 700 "${secret_dir}"

cert_file() {
  printf '%s/%s' "${secret_dir}" "$1"
}

generate_cert_material() {
  local root_key root_crt issuer_conf
  root_key="$(cert_file root.key)"
  root_crt="$(cert_file root.crt)"
  issuer_conf="$(cert_file issuer-openssl.cnf)"

  if [ -s "${root_key}" ] && [ -s "${root_crt}" ] \
    && [ -s "$(cert_file cluster-a-issuer.key)" ] \
    && [ -s "$(cert_file cluster-a-issuer.crt)" ] \
    && [ -s "$(cert_file cluster-b-issuer.key)" ] \
    && [ -s "$(cert_file cluster-b-issuer.crt)" ]; then
    echo "using existing Linkerd identity material in ${secret_dir}"
    return
  fi

  echo "generating Linkerd identity material in ${secret_dir}"
  openssl ecparam -name prime256v1 -genkey -noout -out "${root_key}"
  openssl req -x509 -new -sha256 -nodes \
    -key "${root_key}" \
    -days 3650 \
    -subj "/CN=root.linkerd.cluster.local" \
    -addext "basicConstraints=critical,CA:TRUE" \
    -addext "keyUsage=critical,keyCertSign,cRLSign" \
    -out "${root_crt}"

  cat >"${issuer_conf}" <<'EOF'
[req]
distinguished_name = dn
prompt = no

[dn]
CN = identity.linkerd.cluster.local

[v3_ca]
basicConstraints = critical,CA:TRUE,pathlen:0
keyUsage = critical,keyCertSign,cRLSign
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer
EOF

  for cluster in cluster-a cluster-b; do
    local issuer_key issuer_csr issuer_crt
    issuer_key="$(cert_file "${cluster}-issuer.key")"
    issuer_csr="$(cert_file "${cluster}-issuer.csr")"
    issuer_crt="$(cert_file "${cluster}-issuer.crt")"

    openssl ecparam -name prime256v1 -genkey -noout -out "${issuer_key}"
    openssl req -new -sha256 \
      -key "${issuer_key}" \
      -config "${issuer_conf}" \
      -out "${issuer_csr}"
    openssl x509 -req -sha256 \
      -in "${issuer_csr}" \
      -CA "${root_crt}" \
      -CAkey "${root_key}" \
      -CAcreateserial \
      -days 365 \
      -extfile "${issuer_conf}" \
      -extensions v3_ca \
      -out "${issuer_crt}"
  done

  chmod 600 "${secret_dir}"/*.key
}

require_context() {
  local context="$1"
  kubectl config get-contexts "${context}" >/dev/null 2>&1 \
    || { echo "error: kubectl context '${context}' does not exist" >&2; exit 1; }
}

wait_for_deployments() {
  local context="$1"
  kubectl --context "${context}" -n linkerd rollout status deploy/linkerd-destination --timeout=5m
  kubectl --context "${context}" -n linkerd rollout status deploy/linkerd-identity --timeout=5m
  kubectl --context "${context}" -n linkerd rollout status deploy/linkerd-proxy-injector --timeout=5m
}

install_control_plane() {
  local context="$1"
  local cluster="$2"

  echo "installing Linkerd control plane on ${context}"
  kubectl --context "${context}" create namespace linkerd \
    --dry-run=client -o yaml | kubectl --context "${context}" apply -f -

  helm upgrade --install linkerd-crds linkerd/linkerd-crds \
    --kube-context "${context}" \
    --namespace linkerd \
    --version "${linkerd_crds_chart_version}" \
    --set "enableHttpRoutes=false"

  helm upgrade --install linkerd-control-plane linkerd/linkerd-control-plane \
    --kube-context "${context}" \
    --namespace linkerd \
    --version "${linkerd_control_plane_chart_version}" \
    --set "linkerdVersion=${linkerd_version}" \
    --set "controllerLogLevel=warn" \
    --set "proxy.logLevel=warn,linkerd=info,trust_dns=error" \
    --set-file "identityTrustAnchorsPEM=$(cert_file root.crt)" \
    --set-file "identity.issuer.tls.crtPEM=$(cert_file "${cluster}-issuer.crt")" \
    --set-file "identity.issuer.tls.keyPEM=$(cert_file "${cluster}-issuer.key")"

  wait_for_deployments "${context}"
  linkerd --context "${context}" check --wait=5m
}

gateway_ip_for_context() {
  local context="$1"
  if [ "${context}" = "${cluster_a_context}" ]; then
    echo "${linkerd_gateway_a_ip}"
  else
    echo "${linkerd_gateway_b_ip}"
  fi
}

install_multicluster() {
  local context="$1"
  local mirror_service_account="$2"
  local gateway_ip
  gateway_ip="$(gateway_ip_for_context "${context}")"

  echo "installing Linkerd multicluster extension on ${context}"
  kubectl --context "${context}" create namespace linkerd-multicluster \
    --dry-run=client -o yaml | kubectl --context "${context}" apply -f -

  helm upgrade --install linkerd-multicluster linkerd/linkerd-multicluster \
    --kube-context "${context}" \
    --namespace linkerd-multicluster \
    --version "${linkerd_multicluster_chart_version}" \
    --set "linkerdVersion=${linkerd_version}" \
    --set "gateway.serviceAnnotations.metallb\\.universe\\.tf/loadBalancerIPs=${gateway_ip}" \
    --set "remoteMirrorServiceAccountName=${mirror_service_account}"

  kubectl --context "${context}" -n linkerd-multicluster rollout status deploy/linkerd-gateway --timeout=10m
}

wait_for_gateway_ip() {
  local context="$1"
  local expected_ip="$2"
  local current_ip

  for _ in $(seq 1 60); do
    current_ip="$(
      kubectl --context "${context}" -n linkerd-multicluster get svc linkerd-gateway \
        -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true
    )"
    if [ "${current_ip}" = "${expected_ip}" ]; then
      echo "${context} linkerd-gateway has ${current_ip}"
      return
    fi
    echo "waiting for ${context} linkerd-gateway IP ${expected_ip} (current: ${current_ip:-none})"
    sleep 5
  done

  echo "error: ${context} linkerd-gateway did not get ${expected_ip}" >&2
  exit 1
}

link_clusters() {
  echo "linking cluster-b into cluster-a"
  linkerd --context "${cluster_b_context}" multicluster link \
    --cluster-name cluster-b \
    --service-account-name linkerd-service-mirror-remote-access-cluster-a \
    | kubectl --context "${cluster_a_context}" apply -f -

  echo "linking cluster-a into cluster-b"
  linkerd --context "${cluster_a_context}" multicluster link \
    --cluster-name cluster-a \
    --service-account-name linkerd-service-mirror-remote-access-cluster-b \
    | kubectl --context "${cluster_b_context}" apply -f -
}

verify_multicluster() {
  linkerd --context "${cluster_a_context}" multicluster check --wait=5m
  linkerd --context "${cluster_b_context}" multicluster check --wait=5m
  linkerd --context "${cluster_a_context}" multicluster gateways
  linkerd --context "${cluster_b_context}" multicluster gateways
}

cd "${repo_root}"
require_context "${cluster_a_context}"
require_context "${cluster_b_context}"

helm repo add linkerd https://helm.linkerd.io/stable >/dev/null 2>&1 || true
helm repo update

generate_cert_material

install_control_plane "${cluster_a_context}" cluster-a
install_control_plane "${cluster_b_context}" cluster-b

install_multicluster "${cluster_a_context}" linkerd-service-mirror-remote-access-cluster-b
install_multicluster "${cluster_b_context}" linkerd-service-mirror-remote-access-cluster-a

wait_for_gateway_ip "${cluster_a_context}" "${linkerd_gateway_a_ip}"
wait_for_gateway_ip "${cluster_b_context}" "${linkerd_gateway_b_ip}"

link_clusters
verify_multicluster

cat <<EOF

Linkerd Phase 4 bootstrap complete.

Identity material is stored locally at:
  ${secret_dir}

Do not commit or delete that directory unless you intend to reinstall Linkerd
on both clusters with a new trust anchor.
EOF
