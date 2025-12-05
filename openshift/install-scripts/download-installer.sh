#!/usr/bin/env bash
set -euo pipefail

VERSION="${OPENSHIFT_VERSION:-latest}"
OUT="./openshift-install"

echo "Downloading openshift-install (version: ${VERSION})..."
if [[ "${VERSION}" == "latest" ]]; then
  URL="https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/latest/openshift-install-linux.tar.gz"
else
  URL="https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/${VERSION}/openshift-install-linux.tar.gz"
fi

tmpfile=$(mktemp)
if ! curl -sSL -o "${tmpfile}" "${URL}"; then
  echo "Error: Failed to download openshift-install from ${URL}"
  rm -f "${tmpfile}"
  exit 1
fi

if ! tar -xzf "${tmpfile}" -C .; then
  echo "Error: Failed to extract openshift-install archive"
  rm -f "${tmpfile}"
  exit 1
fi

rm -f "${tmpfile}"
chmod +x ./openshift-install

if [[ ! -f ./openshift-install ]]; then
  echo "Error: openshift-install binary not found after extraction"
  exit 1
fi

echo "Successfully downloaded openshift-install"
./openshift-install version || echo "Warning: Could not display version"