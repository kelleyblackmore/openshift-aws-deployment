#!/usr/bin/env bash
set -euo pipefail

# Script to generate SSH key and upload to AWS as a key pair
# This automates SSH key creation for OpenShift cluster deployment

AWS_REGION="${AWS_REGION:-us-east-1}"
KEY_NAME="${CLUSTER_NAME:-openshift-cluster}-key"
SSH_KEY_PATH="${HOME}/.ssh/openshift-cluster"

# Support non-standard AWS env var names
if [ -n "${AWS_ACCESS_KEY:-}" ] && [ -z "${AWS_ACCESS_KEY_ID:-}" ]; then
  export AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY}"
fi

echo "Setting up SSH key for OpenShift cluster..."

# Check if key already exists
if [ -f "${SSH_KEY_PATH}" ]; then
  echo "SSH key already exists at ${SSH_KEY_PATH}"
else
  echo "Generating new SSH key pair..."
  ssh-keygen -t rsa -b 4096 -f "${SSH_KEY_PATH}" -N "" -C "openshift-cluster-access-$(date +%Y%m%d)"
  echo "SSH key generated at ${SSH_KEY_PATH}"
fi

# Check if key pair exists in AWS
echo "Checking if key pair exists in AWS (${KEY_NAME})..."
if aws ec2 describe-key-pairs --region "${AWS_REGION}" --key-names "${KEY_NAME}" >/dev/null 2>&1; then
  echo "Key pair '${KEY_NAME}' already exists in AWS region ${AWS_REGION}"
  echo "Using existing key pair"
else
  echo "Uploading public key to AWS..."
  aws ec2 import-key-pair \
    --region "${AWS_REGION}" \
    --key-name "${KEY_NAME}" \
    --public-key-material "fileb://${SSH_KEY_PATH}.pub"
  echo "Key pair '${KEY_NAME}' created in AWS region ${AWS_REGION}"
fi

# Export the SSH public key for use in install-config.yaml
export SSH_PUBLIC_KEY=$(cat "${SSH_KEY_PATH}.pub")

echo ""
echo "SSH key setup complete!"
echo "Key name in AWS: ${KEY_NAME}"
echo "Private key location: ${SSH_KEY_PATH}"
echo "Public key location: ${SSH_KEY_PATH}.pub"
echo ""
echo "To use this key, export:"
echo "  export SSH_PUBLIC_KEY=\$(cat ${SSH_KEY_PATH}.pub)"
