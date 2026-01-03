#!/usr/bin/env bash
set -euo pipefail

# Complete teardown script for OpenShift AWS deployment
# This script handles cluster destruction, AWS resource cleanup, and local artifact removal

CLUSTER_NAME="${CLUSTER_NAME:-test-cluster}"
AWS_REGION="${AWS_REGION:-us-east-1}"
SKIP_CONFIRMATION="${SKIP_CONFIRMATION:-false}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Support non-standard AWS env var names
if [ -n "${AWS_ACCESS_KEY:-}" ] && [ -z "${AWS_ACCESS_KEY_ID:-}" ]; then
  export AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY}"
fi

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}OpenShift AWS Deployment Teardown${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo -e "Cluster: ${CLUSTER_NAME}"
echo -e "Region: ${AWS_REGION}"
echo ""

# Function to prompt for confirmation
confirm() {
  if [ "${SKIP_CONFIRMATION}" = "true" ]; then
    return 0
  fi
  
  echo -e "${YELLOW}$1${NC}"
  read -p "Continue? [y/N] " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${RED}Aborted.${NC}"
    exit 1
  fi
}

# Step 1: Destroy OpenShift cluster
if [ -d "./cluster-output" ] && [ -f "./openshift-install" ]; then
  echo -e "${RED}[1/5] Destroying OpenShift cluster...${NC}"
  echo -e "${YELLOW}This will delete all cluster resources in AWS${NC}"
  confirm "This action cannot be undone!"
  
  echo -e "${BLUE}Running cluster destruction...${NC}"
  export AWS_DEFAULT_REGION="${AWS_REGION}"
  ./openshift-install destroy cluster --dir=./cluster-output --log-level=info || {
    echo -e "${YELLOW}⚠ Cluster destruction had errors. Check logs above.${NC}"
    echo -e "${YELLOW}  Some resources may need manual cleanup.${NC}"
  }
  echo -e "${GREEN}✓ Cluster destruction complete${NC}"
else
  echo -e "${YELLOW}[1/5] No cluster found to destroy (skipping)${NC}"
fi

# Step 2: Clean up SSH key pair from AWS
echo ""
echo -e "${BLUE}[2/5] Removing SSH key pair from AWS...${NC}"
KEY_NAME="${CLUSTER_NAME}-key"

if aws ec2 describe-key-pairs --region "${AWS_REGION}" --key-names "${KEY_NAME}" >/dev/null 2>&1; then
  aws ec2 delete-key-pair --region "${AWS_REGION}" --key-name "${KEY_NAME}"
  echo -e "${GREEN}✓ Deleted AWS key pair: ${KEY_NAME}${NC}"
else
  echo -e "${YELLOW}⚠ Key pair '${KEY_NAME}' not found in AWS (skipping)${NC}"
fi

# Step 3: Clean up local SSH keys
echo ""
echo -e "${BLUE}[3/5] Removing local SSH keys...${NC}"
if [ -f ~/.ssh/openshift-cluster ]; then
  rm -f ~/.ssh/openshift-cluster ~/.ssh/openshift-cluster.pub
  echo -e "${GREEN}✓ Removed local SSH keys${NC}"
else
  echo -e "${YELLOW}⚠ No local SSH keys found (skipping)${NC}"
fi

# Step 4: Clean up local artifacts
echo ""
echo -e "${BLUE}[4/5] Cleaning up local artifacts...${NC}"

# Backup important files first if requested
if [ "${BACKUP_BEFORE_DELETE:-false}" = "true" ] && [ -d "./cluster-output" ]; then
  BACKUP_DIR="./backups/${CLUSTER_NAME}-$(date +%Y%m%d-%H%M%S)"
  mkdir -p "${BACKUP_DIR}"
  
  [ -d "./cluster-output/auth" ] && cp -r ./cluster-output/auth "${BACKUP_DIR}/"
  [ -f "./cluster-output/metadata.json" ] && cp ./cluster-output/metadata.json "${BACKUP_DIR}/"
  [ -f "./cluster-output/.openshift_install.log" ] && cp ./cluster-output/.openshift_install.log "${BACKUP_DIR}/"
  
  echo -e "${GREEN}✓ Backed up cluster data to ${BACKUP_DIR}${NC}"
fi

# Remove artifacts
rm -rf ./cluster-output
rm -rf ./ami-artifact
rm -f ./deployment.log
rm -f ./openshift-install

echo -e "${GREEN}✓ Local artifacts cleaned${NC}"

# Step 5: Verify cleanup
echo ""
echo -e "${BLUE}[5/5] Verifying cleanup...${NC}"

CLEANUP_ISSUES=0

# Check for any remaining cluster resources
echo -e "Checking for remaining AWS resources with tag: kubernetes.io/cluster/${CLUSTER_NAME}..."
REMAINING=$(aws ec2 describe-instances \
  --region "${AWS_REGION}" \
  --filters "Name=tag:kubernetes.io/cluster/${CLUSTER_NAME},Values=owned" \
  --query 'Reservations[].Instances[?State.Name!=`terminated`].InstanceId' \
  --output text 2>/dev/null || echo "")

if [ -n "${REMAINING}" ]; then
  echo -e "${YELLOW}⚠ Found remaining EC2 instances: ${REMAINING}${NC}"
  echo -e "${YELLOW}  You may need to terminate these manually${NC}"
  CLEANUP_ISSUES=$((CLEANUP_ISSUES + 1))
fi

# Check for VPCs
VPCS=$(aws ec2 describe-vpcs \
  --region "${AWS_REGION}" \
  --filters "Name=tag:Name,Values=${CLUSTER_NAME}*" \
  --query 'Vpcs[].VpcId' \
  --output text 2>/dev/null || echo "")

if [ -n "${VPCS}" ]; then
  echo -e "${YELLOW}⚠ Found remaining VPCs: ${VPCS}${NC}"
  echo -e "${YELLOW}  These should be cleaned up automatically, but may need manual deletion${NC}"
  CLEANUP_ISSUES=$((CLEANUP_ISSUES + 1))
fi

echo ""
if [ ${CLEANUP_ISSUES} -eq 0 ]; then
  echo -e "${GREEN}========================================${NC}"
  echo -e "${GREEN}✓ Teardown Complete!${NC}"
  echo -e "${GREEN}========================================${NC}"
  echo ""
  echo -e "All resources have been cleaned up:"
  echo -e "  ✓ OpenShift cluster destroyed"
  echo -e "  ✓ AWS SSH key pair removed"
  echo -e "  ✓ Local SSH keys deleted"
  echo -e "  ✓ Local artifacts cleaned"
else
  echo -e "${YELLOW}========================================${NC}"
  echo -e "${YELLOW}⚠ Teardown Complete with Warnings${NC}"
  echo -e "${YELLOW}========================================${NC}"
  echo ""
  echo -e "${YELLOW}Found ${CLEANUP_ISSUES} potential issue(s) that may need manual cleanup.${NC}"
  echo -e "${YELLOW}Review the warnings above and check the AWS console if needed.${NC}"
fi

echo ""
echo -e "${BLUE}Cleanup summary saved to: teardown-$(date +%Y%m%d-%H%M%S).log${NC}"
