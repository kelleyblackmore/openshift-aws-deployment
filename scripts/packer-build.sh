#!/usr/bin/env bash
set -euo pipefail
# Simple helper to call packer with variable overrides and write AMI ID to ami-ids.txt.
AMI_NAME=${1:-"ocp-custom-ami"}
AWS_REGION=${2:-"${AWS_REGION:-us-east-1}"}

echo "Building AMI ${AMI_NAME} in ${AWS_REGION}..."
packer build -var "ami_name=${AMI_NAME}" -var "aws_region=${AWS_REGION}" packer/aws-ami.json | tee packer-out.txt

# Try extracting AMI id
AMI_ID=$(grep -oE 'ami-[0-9a-fA-F]+' packer-out.txt | tail -n1 || true)
if [ -n "$AMI_ID" ]; then
  echo "AMI ID detected: ${AMI_ID}"
  echo "${AMI_ID}" > ami-ids.txt
else
  echo "No AMI ID detected in packer output."
  exit 1
fi