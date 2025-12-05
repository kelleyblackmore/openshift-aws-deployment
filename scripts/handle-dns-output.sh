#!/usr/bin/env bash
set -euo pipefail

# Usage: handle-dns-output.sh <cluster-output-dir>
OUT_DIR="${1:-./cluster-output}"
if [[ ! -d "${OUT_DIR}" ]]; then
  echo "Cluster output dir not found: ${OUT_DIR}"
  exit 1
fi

DNS_PROVIDER="${DNS_PROVIDER:-route53}"
HOSTED_ZONE_ID="${HOSTED_ZONE_ID:-}"

METADATA_FILE="${OUT_DIR}/metadata.json"
INSTALL_CONFIG="${OUT_DIR}/install-config.yaml"

INFRA_ID=""
if [[ -f "${METADATA_FILE}" ]]; then
  if command -v jq >/dev/null 2>&1; then
    INFRA_ID=$(jq -r '.infraID // empty' "${METADATA_FILE}" || true)
  fi
fi

CLUSTER_NAME=""
BASE_DOMAIN=""
if [[ -f "${INSTALL_CONFIG}" ]]; then
  CLUSTER_NAME=$(grep -E '^  name:' -m1 "${INSTALL_CONFIG}" | awk '{print $2}' || true)
  BASE_DOMAIN=$(grep -E '^baseDomain:' -m1 "${INSTALL_CONFIG}" | awk '{print $2}' || true)
fi

echo "DNS provider: ${DNS_PROVIDER}"
echo "Cluster: ${CLUSTER_NAME}.${BASE_DOMAIN}"
echo "InfraID: ${INFRA_ID}"

if [[ "${DNS_PROVIDER}" == "route53" ]]; then
  if [[ -z "${HOSTED_ZONE_ID}" ]]; then
    echo "HOSTED_ZONE_ID not provided. Please supply it to verify Route53 records."
    exit 0
  fi
  if ! command -v aws >/dev/null 2>&1; then
    echo "aws CLI not present; cannot verify Route53 records. Skipping."
    exit 0
  fi
  aws route53 list-resource-record-sets --hosted-zone-id "${HOSTED_ZONE_ID}" \
    --query "ResourceRecordSets[?contains(Name, '${CLUSTER_NAME}') || contains(Name, 'api.${CLUSTER_NAME}') || contains(Name, 'apps.${CLUSTER_NAME}')]" \
    --output table || true
  exit 0
fi

# For user-managed DNS: try to locate LB DNS names and provide records
if ! command -v aws >/dev/null 2>&1; then
  echo "aws CLI not present; cannot query Load Balancers. Please check the cluster load balancers manually."
  echo "Required records:"
  echo "  api.${CLUSTER_NAME}.${BASE_DOMAIN} -> <API LB DNS>"
  echo "  *.apps.${CLUSTER_NAME}.${BASE_DOMAIN} -> <Apps LB DNS>"
  exit 0
fi

LBS_FULL=$(aws elbv2 describe-load-balancers --output json)

API_LB_DNS=""
APPS_LB_DNS=""

for arn in $(echo "${LBS_FULL}" | jq -r '.LoadBalancers[].LoadBalancerArn'); do
  tags=$(aws elbv2 describe-tags --resource-arns "${arn}" --output json)
  match=false
  if [[ -n "${INFRA_ID}" ]]; then
    if echo "${tags}" | jq -e --arg id "${INFRA_ID}" '.[].Tags[]? | select(.Key | contains($id) or (.Value | contains($id)))' >/dev/null 2>&1; then
      match=true
    fi
  fi
  if ! $match && [[ -n "${CLUSTER_NAME}" ]]; then
    if echo "${tags}" | jq -e --arg name "${CLUSTER_NAME}" '.[].Tags[]? | select(.Key | contains($name) or (.Value | contains($name)))' >/dev/null 2>&1; then
      match=true
    fi
  fi

  if [[ "$match" == "true" || "$match" == "True" ]]; then
    dns=$(echo "${LBS_FULL}" | jq -r --arg arn "${arn}" '.LoadBalancers[] | select(.LoadBalancerArn == $arn) | .DNSName')
    name=$(echo "${LBS_FULL}" | jq -r --arg arn "${arn}" '.LoadBalancers[] | select(.LoadBalancerArn == $arn) | .LoadBalancerName')
    if echo "${name}" | grep -Eiq 'api|apiserver'; then
      API_LB_DNS="${dns}"
    elif echo "${name}" | grep -Eiq 'apps|router|ingress'; then
      APPS_LB_DNS="${dns}"
    else
      if [[ -z "${APPS_LB_DNS}" ]]; then
        APPS_LB_DNS="${dns}"
      fi
    fi
  fi
done

echo ""
echo "Suggested DNS records to create:"
if [[ -n "${API_LB_DNS}" ]]; then
  echo " - api.${CLUSTER_NAME}.${BASE_DOMAIN}  -> CNAME  ${API_LB_DNS}"
else
  echo " - api.${CLUSTER_NAME}.${BASE_DOMAIN}  -> <API Load Balancer DNS name> (not detected)"
fi

if [[ -n "${APPS_LB_DNS}" ]]; then
  echo " - *.apps.${CLUSTER_NAME}.${BASE_DOMAIN}  -> CNAME  ${APPS_LB_DNS}"
else
  echo " - *.apps.${CLUSTER_NAME}.${BASE_DOMAIN}  -> <Apps Load Balancer DNS name> (not detected)"
fi

echo ""
echo "Please create the suggested CNAMEs in your DNS provider and allow propagation."