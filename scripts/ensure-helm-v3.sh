#!/usr/bin/env bash
# Ensure a Helm v3 binary is available for `kubectl kustomize --enable-helm`.
# Kustomize currently shells out with Helm v3 flags, so host Helm v4 is not
# compatible. This installs a repo-local Helm v3 under .tools/ without sudo.
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/env.sh
source "${script_dir}/lib/env.sh"

helm_version="${HELM_V3_VERSION:-v3.18.6}"
tool_dir="${repo_root}/.tools/helm-${helm_version}"
helm_bin="${tool_dir}/linux-amd64/helm"

if [ -x "${helm_bin}" ]; then
  echo "${tool_dir}/linux-amd64"
  exit 0
fi

mkdir -p "${tool_dir}"
archive="${tool_dir}/helm-${helm_version}-linux-amd64.tar.gz"
url="https://get.helm.sh/helm-${helm_version}-linux-amd64.tar.gz"

echo "downloading Helm ${helm_version} to ${tool_dir}" >&2
curl -fsSL "${url}" -o "${archive}"
tar -xzf "${archive}" -C "${tool_dir}"
chmod +x "${helm_bin}"

echo "${tool_dir}/linux-amd64"
