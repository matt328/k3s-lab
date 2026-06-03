#!/usr/bin/env bash
# Install Argo CD on cluster A using the community Helm chart via
# `kubectl kustomize --enable-helm`, register cluster B, then apply the root
# Application so Argo CD manages itself from this repository.
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/env.sh
source "${script_dir}/lib/env.sh"

require_env GITOPS_REPO_URL
require_env GITOPS_REPO_REVISION
require_env GITOPS_REPO_PATH

cluster_a_context="${CLUSTER_A_CONTEXT:-cluster-a}"
namespace="${ARGOCD_NAMESPACE:-argocd}"

cd "${repo_root}"

if ! git ls-remote --exit-code "${GITOPS_REPO_URL}" "${GITOPS_REPO_REVISION}" >/dev/null 2>&1; then
  echo "error: ${GITOPS_REPO_URL} ${GITOPS_REPO_REVISION} is not reachable." >&2
  echo "Commit and push this repository before bootstrapping Argo CD." >&2
  exit 1
fi

if ! kubectl kustomize --help 2>&1 | grep -q -- '--enable-helm'; then
  echo "error: kubectl kustomize does not support --enable-helm." >&2
  exit 1
fi

helm_path="$("${script_dir}/ensure-helm-v3.sh")"
export PATH="${helm_path}:${PATH}"

kubectl --context "${cluster_a_context}" create namespace "${namespace}" \
  --dry-run=client -o yaml | kubectl --context "${cluster_a_context}" apply -f -

echo "installing/upgrading Argo CD from argocd/ Helm chart"
rm -rf argocd/charts
kubectl kustomize --enable-helm argocd \
  | kubectl --context "${cluster_a_context}" apply -f -

echo "waiting for Argo CD deployments"
kubectl --context "${cluster_a_context}" -n "${namespace}" rollout status deploy/argocd-redis --timeout=5m
kubectl --context "${cluster_a_context}" -n "${namespace}" rollout status deploy/argocd-repo-server --timeout=5m
kubectl --context "${cluster_a_context}" -n "${namespace}" rollout status deploy/argocd-server --timeout=5m
kubectl --context "${cluster_a_context}" -n "${namespace}" rollout status deploy/argocd-applicationset-controller --timeout=5m

"${script_dir}/register-cluster-b.sh"

echo "applying root bootstrap Application"
kubectl --context "${cluster_a_context}" apply -f gitops/bootstrap/root-application.yaml

echo
echo "Argo CD bootstrap complete."
echo "Port-forward UI with:"
echo "  kubectl --context ${cluster_a_context} -n ${namespace} port-forward svc/argocd-server 8080:80"
echo
echo "Initial admin password:"
echo "  kubectl --context ${cluster_a_context} -n ${namespace} get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo"
