#!/usr/bin/env bash
set -euo pipefail

# Usage: prepare-config.sh --cluster-name NAME --region REGION --dns-provider route53|user-managed|cloudflare \
#   [--hosted-zone-id Z] [--hosted-zone-name NAME] [--worker-ami AMI] [--control-ami AMI]

CLUSTER_NAME=""
AWS_REGION=""
DNS_PROVIDER=""
HOSTED_ZONE_ID=""
HOSTED_ZONE_NAME=""
WORKER_AMI="${WORKER_AMI:-}"
CONTROL_AMI="${CONTROL_AMI:-}"
BASE_DOMAIN="${BASE_DOMAIN:-example.com}"

# parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --cluster-name) CLUSTER_NAME="$2"; shift 2;;
    --region) AWS_REGION="$2"; shift 2;;
    --dns-provider) DNS_PROVIDER="$2"; shift 2;;
    --hosted-zone-id) HOSTED_ZONE_ID="$2"; shift 2;;
    --hosted-zone-name) HOSTED_ZONE_NAME="$2"; shift 2;;
    --worker-ami) WORKER_AMI="$2"; shift 2;;
    --control-ami) CONTROL_AMI="$2"; shift 2;;
    *) echo "Unknown arg: $1"; shift ;;
  esac
done

if [[ -z "$CLUSTER_NAME" || -z "$AWS_REGION" || -z "$DNS_PROVIDER" ]]; then
  echo "Required args: --cluster-name, --region, --dns-provider"
  exit 1
fi

if [[ "${DNS_PROVIDER}" == "route53" ]]; then
  if [[ -z "$HOSTED_ZONE_ID" || -z "$HOSTED_ZONE_NAME" ]]; then
    echo "For route53 provider you must provide --hosted-zone-id and --hosted-zone-name"
    exit 1
  fi
  TEMPLATE="configs/aws-install-config.route53.yaml.tpl"
elif [[ "${DNS_PROVIDER}" == "user-managed" ]]; then
  TEMPLATE="configs/aws-install-config.usermanaged.yaml.tpl"
else
  echo "dns-provider must be 'route53' or 'user-managed'"
  exit 1
fi

# Ensure required envs are present (these are typically set by CI via secrets)
if [[ -z "${OPENSHIFT_PULL_SECRET:-}" ]]; then
  echo "OPENSHIFT_PULL_SECRET env var is required (set this in your CI secrets)"
  exit 1
fi
if [[ -z "${SSH_PUBLIC_KEY:-}" ]]; then
  echo "SSH_PUBLIC_KEY env var is required (set this in your CI secrets)"
  exit 1
fi

# If user asked to use latest AMIs artifact, prefer ami-ids.txt if present in workspace (downloaded by workflow)
if [[ -z "${WORKER_AMI}" && -f ./ami-artifact/ami-ids.txt ]]; then
  WORKER_AMI=$(sed -n '1p' ./ami-artifact/ami-ids.txt || true)
  echo "Using worker AMI from artifact: ${WORKER_AMI}"
fi
if [[ -z "${CONTROL_AMI}" && -f ./ami-artifact/ami-ids.txt ]]; then
  CONTROL_AMI=$(sed -n '1p' ./ami-artifact/ami-ids.txt || true)
  echo "Using control AMI from artifact: ${CONTROL_AMI}"
fi

export CLUSTER_NAME AWS_REGION HOSTED_ZONE_ID HOSTED_ZONE_NAME WORKER_AMI CONTROL_AMI BASE_DOMAIN
export OPENSHIFT_PULL_SECRET SSH_PUBLIC_KEY

# Output dir
mkdir -p ./cluster-output

# Compose environment substitutions - set defaults explicitly
WORKER_REPLICAS=${WORKER_REPLICAS:-3}
CONTROL_REPLICAS=${CONTROL_REPLICAS:-3}
WORKER_INSTANCE_TYPE=${WORKER_INSTANCE_TYPE:-m5.xlarge}
CONTROL_INSTANCE_TYPE=${CONTROL_INSTANCE_TYPE:-m5.xlarge}

export WORKER_REPLICAS CONTROL_REPLICAS WORKER_INSTANCE_TYPE CONTROL_INSTANCE_TYPE

# Create install-config.yaml using envsubst and clean up empty amiID lines
envsubst < "${TEMPLATE}" | grep -v '^[[:space:]]*amiID:[[:space:]]*$' > ./cluster-output/install-config.yaml

echo "Created install-config at ./cluster-output/install-config.yaml"
echo "----"
echo "Cluster: ${CLUSTER_NAME}.${BASE_DOMAIN}"
echo "DNS provider: ${DNS_PROVIDER}"
if [[ "${DNS_PROVIDER}" == "route53" ]]; then
  echo "Route53 Hosted Zone ID: ${HOSTED_ZONE_ID}"
  echo "Route53 Hosted Zone Name: ${HOSTED_ZONE_NAME}"
fi

# For user-managed DNS, installer will output DNS records you must create; handle-dns-output.sh prints them post-deploy.
if [[ "${DNS_PROVIDER}" == "user-managed" ]]; then
  echo "Note: user-managed DNS selected. After the installer finishes, run the DNS helper to obtain required records or use the 'Handle DNS output' step in CI."
fi