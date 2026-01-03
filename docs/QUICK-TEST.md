# Quick Test Deployment Guide

This guide walks you through testing OpenShift deployment on AWS with automated SSH key management.

## Prerequisites

1. AWS credentials set (supports non-standard variable names):
   ```bash
   export AWS_ACCESS_KEY=your-key-here
   export AWS_SECRET_ACCESS_KEY=your-secret-here
   ```

2. OpenShift pull secret from https://console.redhat.com/openshift/install/pull-secret

## Automated Test Deployment

### Option 1: Using the automated script

```bash
# Set your pull secret first
export OPENSHIFT_PULL_SECRET='{"auths":...}'

# Run automated setup (handles SSH key generation and upload)
make quick-test
```

### Option 2: Step-by-step

```bash
# 1. Check environment
make check-env
make check-credentials

# 2. Auto-generate and upload SSH key to AWS
make setup-ssh-key CLUSTER_NAME=test-cluster AWS_REGION=us-east-1

# 3. Export the SSH key
export SSH_PUBLIC_KEY=$(cat ~/.ssh/openshift-cluster.pub)

# 4. Set your OpenShift pull secret
export OPENSHIFT_PULL_SECRET='{"auths":...}'

# 5. Download installer
make download-installer

# 6. Generate configuration
make validate-config CLUSTER_NAME=test-cluster BASE_DOMAIN=example.com

# 7. Review configuration
make show-config

# 8. Deploy (or dry-run first)
make dry-run          # Optional: generate manifests without deploying
make create-cluster   # Deploy the cluster
```

## What the Automation Does

The `setup-ssh-key` target automatically:
- Generates a 4096-bit RSA SSH key pair at `~/.ssh/openshift-cluster`
- Uploads the public key to AWS EC2 as a key pair named `<cluster-name>-key`
- Handles non-standard AWS credential variable names (`AWS_ACCESS_KEY` → `AWS_ACCESS_KEY_ID`)
- Reuses existing keys if already present

## SSH Key Location

- Private key: `~/.ssh/openshift-cluster`
- Public key: `~/.ssh/openshift-cluster.pub`
- AWS key pair name: `<cluster-name>-key` (e.g., `test-cluster-key`)

## Configuration Variables

You can customize your deployment:

```bash
make validate-config \
  CLUSTER_NAME=my-cluster \
  AWS_REGION=us-west-2 \
  BASE_DOMAIN=mycompany.com \
  WORKER_REPLICAS=3 \
  CONTROL_REPLICAS=3 \
  WORKER_INSTANCE_TYPE=m5.xlarge \
  CONTROL_INSTANCE_TYPE=m5.xlarge
```

## Clean Up

Remove the SSH key from AWS:
```bash
aws ec2 delete-key-pair --region us-east-1 --key-name test-cluster-key
```

Remove local SSH key:
```bash
rm ~/.ssh/openshift-cluster ~/.ssh/openshift-cluster.pub
```

Destroy cluster:
```bash
make destroy-cluster
```
