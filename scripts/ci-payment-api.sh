#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/env.sh
source "${repo_root}/scripts/lib/env.sh"

mode="${1:-}"
branch_name="${2:-$(git -C "${repo_root}" rev-parse --abbrev-ref HEAD 2>/dev/null || echo local)}"
project_dir="${repo_root}/apps/apis/payment-api"
repository_url="${PAYMENT_API_MAVEN_REPOSITORY_URL:-${ARTIFACT_REGISTRY_RELEASES_URL:?}}"
username="${ARTIFACT_REGISTRY_ADMIN_USER:-admin}"
token_file="${ARTIFACT_REGISTRY_TOKEN_FILE:-${repo_root}/.secrets/reposilite/admin-token}"

if [ "${mode}" != "feature" ] && [ "${mode}" != "main" ]; then
  echo "usage: $0 <feature|main> [branch-name]" >&2
  exit 1
fi

if [ ! -x "${project_dir}/gradlew" ]; then
  echo "error: ${project_dir}/gradlew is missing or not executable" >&2
  exit 1
fi

if [ ! -f "${token_file}" ]; then
  echo "error: ${token_file} does not exist; run ./scripts/bootstrap-artifact-registry.sh first" >&2
  exit 1
fi

base_version="$(grep '^version=' "${project_dir}/gradle.properties" | cut -d= -f2-)"
short_sha="$(git -C "${repo_root}" rev-parse --short HEAD 2>/dev/null || date +%s)"

case "${mode}" in
  main)
    version="${PAYMENT_API_RELEASE_VERSION:-${base_version}}"
    ;;
  feature)
    branch_slug="$(printf '%s' "${branch_name#feature/}" \
      | tr '[:upper:]' '[:lower:]' \
      | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//')"
    if [ -z "${branch_slug}" ]; then
      branch_slug="feature"
    fi
    version="${PAYMENT_API_PRERELEASE_VERSION:-${base_version}-${branch_slug}.${short_sha}}"
    ;;
esac

password="$(tr -d '\n' <"${token_file}")"
artifact_path="dev/teeter/demos/apis/payment-api-spec/${version}/payment-api-spec-${version}.yaml"

echo "Payment API CI simulation"
echo "  mode:       ${mode}"
echo "  branch:     ${branch_name}"
echo "  version:    ${version}"
echo "  repository: ${repository_url}"

(
  cd "${project_dir}"
  ./gradlew --no-daemon clean validateOpenApi publish \
    -Pversion="${version}" \
    -PmavenRepositoryUrl="${repository_url}" \
    -PmavenRepositoryUsername="${username}" \
    -PmavenRepositoryPassword="${password}"
)

tmp_file="$(mktemp)"
trap 'rm -f "${tmp_file}"' EXIT

curl -fsS -u "${username}:${password}" \
  "${repository_url}/${artifact_path}" \
  -o "${tmp_file}"

if ! grep -q "version: ${version}" "${tmp_file}"; then
  echo "error: published artifact does not contain expected OpenAPI version ${version}" >&2
  exit 1
fi

cat <<EOF
Published Payment API artifact:
  dev.teeter.demos.apis:payment-api-spec:${version}@yaml

Resolved from:
  ${repository_url}/${artifact_path}
EOF
