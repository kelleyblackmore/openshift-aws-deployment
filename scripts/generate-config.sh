#!/usr/bin/env bash
set -euo pipefail

# Helper script to generate install-config.yaml with conditional AMI fields

OUTPUT_FILE="$1"
TEMPLATE="$2"

# Read template
CONTENT=$(<"${TEMPLATE}")

# Replace all variables
CONTENT=$(echo "$CONTENT" | envsubst)

# Remove empty amiID lines if AMI variables are not set
if [[ -z "${WORKER_AMI:-}" ]]; then
  CONTENT=$(echo "$CONTENT" | grep -v "amiID: $" | sed '/^[[:space:]]*amiID:[[:space:]]*$/d')
fi

if [[ -z "${CONTROL_AMI:-}" ]]; then
  CONTENT=$(echo "$CONTENT" | grep -v "amiID: $" | sed '/^[[:space:]]*amiID:[[:space:]]*$/d')
fi

# Write output
echo "$CONTENT" > "${OUTPUT_FILE}"
