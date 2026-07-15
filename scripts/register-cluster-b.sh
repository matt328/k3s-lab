#!/usr/bin/env bash
# Register cluster B with the Argo CD instance running in cluster A.
#
# The generated Argo CD cluster secret is applied directly to cluster A and is
# not written into the repository because it contains a bearer token.
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/env.sh
source "${script_dir}/lib/env.sh"

require_env CLUSTER_B_SERVER_1_IP

cluster_a_context="${CLUSTER_A_CONTEXT:-cluster-a}"
cluster_b_context="${CLUSTER_B_CONTEXT:-cluster-b}"
namespace="${ARGOCD_NAMESPACE:-argocd}"
service_account="${ARGOCD_CLUSTER_B_SERVICE_ACCOUNT:-argocd-manager}"
token_secret="${service_account}-token"

kubectl --context "${cluster_b_context}" create namespace argocd-manager \
  --dry-run=client -o yaml | kubectl --context "${cluster_b_context}" apply -f -

kubectl --context "${cluster_b_context}" -n argocd-manager create serviceaccount "${service_account}" \
  --dry-run=client -o yaml | kubectl --context "${cluster_b_context}" apply -f -

kubectl --context "${cluster_b_context}" create clusterrolebinding "${service_account}" \
  --clusterrole=cluster-admin \
  --serviceaccount="argocd-manager:${service_account}" \
  --dry-run=client -o yaml | kubectl --context "${cluster_b_context}" apply -f -

kubectl --context "${cluster_b_context}" -n argocd-manager apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: ${token_secret}
  annotations:
    kubernetes.io/service-account.name: ${service_account}
type: kubernetes.io/service-account-token
EOF

for i in $(seq 1 30); do
  token_data="$(kubectl --context "${cluster_b_context}" -n argocd-manager get secret "${token_secret}" -o jsonpath='{.data.token}' 2>/dev/null || true)"
  if [ -n "${token_data}" ]; then
    break
  fi
  echo "waiting for ${token_secret} to be populated ($i/30)..."
  sleep 1
done

if [ -z "${token_data:-}" ]; then
  echo "error: ${token_secret} was not populated with a service account token" >&2
  exit 1
fi

token="$(printf '%s' "${token_data}" | base64 -d)"
ca_data="$(kubectl --context "${cluster_b_context}" config view --raw -o jsonpath='{.clusters[?(@.name=="cluster-b")].cluster.certificate-authority-data}')"
server="https://${CLUSTER_B_SERVER_1_IP}:6443"

config_json="$(kubectl create configmap cluster-b-config \
  --from-literal=config="{\"bearerToken\":\"${token}\",\"tlsClientConfig\":{\"insecure\":false,\"caData\":\"${ca_data}\"}}" \
  --dry-run=client -o jsonpath='{.data.config}')"

kubectl --context "${cluster_a_context}" -n "${namespace}" create secret generic cluster-b \
  --from-literal=name=cluster-b \
  --from-literal=server="${server}" \
  --from-literal=config="${config_json}" \
  --dry-run=client -o yaml \
  | kubectl --context "${cluster_a_context}" label -f - \
      argocd.argoproj.io/secret-type=cluster \
      --local -o yaml \
  | kubectl --context "${cluster_a_context}" apply -f -

echo "registered cluster-b (${server}) with Argo CD in ${cluster_a_context}/${namespace}"
