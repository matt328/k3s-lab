#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/env.sh
source "${repo_root}/scripts/lib/env.sh"

mode="${1:-}"
branch_name="${2:-$(git -C "${repo_root}" rev-parse --abbrev-ref HEAD 2>/dev/null || echo local)}"
project_dir="${repo_root}/apps/services/payment-service"
maven_repository_url="${PAYMENT_API_MAVEN_REPOSITORY_URL:-${ARTIFACT_REGISTRY_RELEASES_URL:?}}"
image_repository="${PAYMENT_SERVICE_IMAGE_REPOSITORY:?}"
payment_api_version="${PAYMENT_API_VERSION:-0.1.0}"

if [ "${mode}" != "feature" ] && [ "${mode}" != "main" ]; then
  echo "usage: $0 <feature|main> [branch-name]" >&2
  exit 1
fi

if [ ! -x "${project_dir}/gradlew" ]; then
  echo "error: ${project_dir}/gradlew is missing or not executable" >&2
  exit 1
fi

if ! command -v skopeo >/dev/null 2>&1; then
  echo "error: skopeo is required to inspect the pushed image digest" >&2
  exit 1
fi

base_version="$(grep '^version=' "${project_dir}/gradle.properties" | cut -d= -f2-)"
short_sha="$(git -C "${repo_root}" rev-parse --short HEAD 2>/dev/null || date +%s)"

case "${mode}" in
  main)
    image_tag="${PAYMENT_SERVICE_RELEASE_VERSION:-${base_version}}"
    ;;
  feature)
    branch_slug="$(printf '%s' "${branch_name#feature/}" \
      | tr '[:upper:]' '[:lower:]' \
      | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//')"
    if [ -z "${branch_slug}" ]; then
      branch_slug="feature"
    fi
    image_tag="${PAYMENT_SERVICE_PRERELEASE_VERSION:-${base_version}-${branch_slug}.${short_sha}}"
    ;;
esac

api_artifact_url="${maven_repository_url}/dev/teeter/demos/apis/payment-api-spec/${payment_api_version}/payment-api-spec-${payment_api_version}.yaml"
image_ref="${image_repository}:${image_tag}"

if ! curl -fsS "${api_artifact_url}" >/dev/null; then
  echo "error: Payment API artifact is not available: ${api_artifact_url}" >&2
  echo "hint: run ./scripts/ci-payment-api.sh main first" >&2
  exit 1
fi

if skopeo inspect --tls-verify=false "docker://${image_ref}" >/dev/null 2>&1; then
  echo "error: image tag already exists and tags are treated as immutable: ${image_ref}" >&2
  echo "hint: use a new version/tag or set PAYMENT_SERVICE_PRERELEASE_VERSION/PAYMENT_SERVICE_RELEASE_VERSION" >&2
  exit 1
fi

echo "Payment service CI simulation"
echo "  mode:                ${mode}"
echo "  branch:              ${branch_name}"
echo "  image:               ${image_ref}"
echo "  payment API version: ${payment_api_version}"
echo "  Maven repository:    ${maven_repository_url}"

(
  cd "${project_dir}"
  ./gradlew --no-daemon clean test jib \
    -Pversion="${image_tag}" \
    -PpaymentApiVersion="${payment_api_version}" \
    -PmavenRepositoryUrl="${maven_repository_url}" \
    -PimageRepository="${image_repository}" \
    -PimageTag="${image_tag}"
)

digest="$(skopeo inspect --tls-verify=false "docker://${image_ref}" --format '{{.Digest}}')"

cat <<EOF
Published Payment service image:
  ${image_ref}@${digest}

Helm values shape:
  image:
    repository: ${image_repository}
    tag: ${image_tag}
    digest: ${digest}
EOF
