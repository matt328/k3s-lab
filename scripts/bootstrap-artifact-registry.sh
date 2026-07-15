#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/env.sh
source "${repo_root}/scripts/lib/env.sh"

context="${ARTIFACT_REGISTRY_CONTEXT:-cluster-b}"
namespace="${ARTIFACT_REGISTRY_NAMESPACE:-artifact-registry}"
secret_name="${ARTIFACT_REGISTRY_SECRET_NAME:-reposilite-bootstrap-token}"
admin_user="${ARTIFACT_REGISTRY_ADMIN_USER:-admin}"
token_file="${ARTIFACT_REGISTRY_TOKEN_FILE:-${repo_root}/.secrets/reposilite/admin-token}"
artifact_registry_url="${ARTIFACT_REGISTRY_URL:?}"
artifact_registry_releases_url="${ARTIFACT_REGISTRY_RELEASES_URL:?}"
artifact_registry_snapshots_url="${ARTIFACT_REGISTRY_SNAPSHOTS_URL:?}"

mkdir -p "$(dirname "${token_file}")"
chmod 700 "$(dirname "${token_file}")"

if [ ! -f "${token_file}" ]; then
  umask 077
  openssl rand -hex 24 >"${token_file}"
fi

admin_token="$(tr -d '\n' <"${token_file}")"

kubectl --context "${context}" create namespace "${namespace}" \
  --dry-run=client -o yaml | kubectl --context "${context}" apply -f -

kubectl --context "${context}" -n "${namespace}" create secret generic "${secret_name}" \
  --from-literal="REPOSILITE_OPTS=--token ${admin_user}:${admin_token}" \
  --from-literal="username=${admin_user}" \
  --from-literal="password=${admin_token}" \
  --dry-run=client -o yaml | kubectl --context "${context}" apply -f -

if kubectl --context "${context}" -n "${namespace}" get deploy/reposilite >/dev/null 2>&1; then
  kubectl --context "${context}" -n "${namespace}" rollout restart deploy/reposilite
  kubectl --context "${context}" -n "${namespace}" rollout status deploy/reposilite --timeout=5m
fi

cat <<EOF
Reposilite bootstrap token is applied.

URL:
  ${artifact_registry_url}

Maven repositories:
  ${artifact_registry_releases_url}
  ${artifact_registry_snapshots_url}

Credentials:
  username: ${admin_user}
  password file: ${token_file}
EOF
