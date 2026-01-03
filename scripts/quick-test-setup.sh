#!/usr/bin/env bash
set -euo pipefail

# Quick test deployment script for OpenShift on AWS
# This script automates the entire setup for testing purposes

echo "=========================================="
echo "OpenShift AWS Test Deployment"
echo "=========================================="
echo ""

# Default values
CLUSTER_NAME="${CLUSTER_NAME:-test-cluster}"
AWS_REGION="${AWS_REGION:-us-east-1}"
BASE_DOMAIN="${BASE_DOMAIN:-example.com}"
DNS_PROVIDER="${DNS_PROVIDER:-user-managed}"

echo "Configuration:"
echo "  Cluster Name: ${CLUSTER_NAME}"
echo "  AWS Region: ${AWS_REGION}"
echo "  Base Domain: ${BASE_DOMAIN}"
echo "  DNS Provider: ${DNS_PROVIDER}"
echo ""

# Step 1: Check dependencies
echo "[1/6] Checking dependencies..."
make check-env

# Step 2: Verify AWS credentials
echo ""
echo "[2/6] Verifying AWS credentials..."
make check-credentials

# Step 3: Setup SSH key
echo ""
echo "[3/6] Setting up SSH key..."
make setup-ssh-key CLUSTER_NAME="${CLUSTER_NAME}" AWS_REGION="${AWS_REGION}"

# Export SSH key
export SSH_PUBLIC_KEY=$(cat ~/.ssh/openshift-cluster.pub)
echo "SSH_PUBLIC_KEY exported"

# Step 4: Download installer
echo ""
echo "[4/6] Downloading OpenShift installer..."
make download-installer

# Step 5: Check for pull secret
echo ""
echo "[5/6] Checking for OpenShift pull secret..."
if [ -z "${OPENSHIFT_PULL_SECRET:-}" ]; then
  echo ""
  echo "=========================================="
  echo "ACTION REQUIRED: OpenShift Pull Secret"
  echo "=========================================="
  echo ""
  echo "You need to obtain your OpenShift pull secret:"
  echo "  1. Visit: https://console.redhat.com/openshift/install/pull-secret"
  echo "  2. Copy the pull secret (it's a JSON string)"
  echo "  3. Export it:"
  echo ""
  echo "     export OPENSHIFT_PULL_SECRET='<paste-your-secret-here>'"
  echo ""
  echo "Then re-run this script or continue with:"
  echo "  make validate-config CLUSTER_NAME=${CLUSTER_NAME} AWS_REGION=${AWS_REGION} BASE_DOMAIN=${BASE_DOMAIN}"
  echo ""
  exit 1
fi

echo "Pull secret found"

# Step 6: Generate config
echo ""
echo "[6/6] Generating install-config.yaml..."
make validate-config \
  CLUSTER_NAME="${CLUSTER_NAME}" \
  AWS_REGION="${AWS_REGION}" \
  BASE_DOMAIN="${BASE_DOMAIN}" \
  DNS_PROVIDER="${DNS_PROVIDER}"

echo ""
echo "=========================================="
echo "Setup Complete!"
echo "=========================================="
echo ""
echo "Your cluster configuration is ready at:"
echo "  ./cluster-output/install-config.yaml"
echo ""
echo "Next steps:"
echo "  1. Review config: make show-config"
echo "  2. Dry run (optional): make dry-run"
echo "  3. Deploy cluster: make create-cluster"
echo ""
echo "To deploy now, run:"
echo "  make create-cluster"
echo ""
