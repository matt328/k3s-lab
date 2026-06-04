#!/usr/bin/env bash
# Ensure the Linkerd CLI matching the pinned Helm chart app version is available.
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/env.sh
source "${script_dir}/lib/env.sh"

linkerd_version="${LINKERD_VERSION:-stable-2.14.10}"
tool_dir="${repo_root}/.tools/linkerd-${linkerd_version}"
linkerd_bin="${tool_dir}/linkerd"

if [ -x "${linkerd_bin}" ]; then
  echo "${tool_dir}"
  exit 0
fi

mkdir -p "${tool_dir}"
asset="linkerd2-cli-${linkerd_version}-linux-amd64"
url="https://github.com/linkerd/linkerd2/releases/download/${linkerd_version}/${asset}"
checksum_url="${url}.sha256"

echo "downloading Linkerd CLI ${linkerd_version} to ${tool_dir}" >&2
curl -fsSL "${url}" -o "${linkerd_bin}"
curl -fsSL "${checksum_url}" -o "${linkerd_bin}.sha256"

expected="$(awk '{print $1}' "${linkerd_bin}.sha256")"
actual="$(sha256sum "${linkerd_bin}" | awk '{print $1}')"
if [ "${expected}" != "${actual}" ]; then
  rm -f "${linkerd_bin}" "${linkerd_bin}.sha256"
  echo "error: checksum mismatch for Linkerd CLI ${linkerd_version}" >&2
  exit 1
fi

chmod +x "${linkerd_bin}"
echo "${tool_dir}"
