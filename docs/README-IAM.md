# AWS IAM Policy for OpenShift Installation

This document describes the IAM permissions required for the OpenShift installer to provision and manage infrastructure on AWS.

## Policy File

The complete IAM policy is available in [`aws-iam-policy.json`](./aws-iam-policy.json).

## How to Use

### Option 1: Create IAM User with Policy

```bash
# Create a new IAM user for OpenShift installations
aws iam create-user --user-name openshift-installer

# Attach the policy to the user
aws iam put-user-policy \
  --user-name openshift-installer \
  --policy-name OpenShiftInstallerPolicy \
  --policy-document file://docs/aws-iam-policy.json

# Create access keys for the user
aws iam create-access-key --user-name openshift-installer
```

### Option 2: Create IAM Role for CI/CD

```bash
# Create the policy first
aws iam create-policy \
  --policy-name OpenShiftInstallerPolicy \
  --policy-document file://docs/aws-iam-policy.json

# Attach to your CI/CD role or instance profile
aws iam attach-role-policy \
  --role-name YourCIRole \
  --policy-arn arn:aws:iam::ACCOUNT_ID:policy/OpenShiftInstallerPolicy
```

## Permissions Summary

### EC2 Permissions
Full control over compute instances, networking (VPC, subnets, security groups), and storage volumes.

### Elastic Load Balancing
Create and manage Network and Application Load Balancers for cluster API and ingress traffic.

### IAM Permissions
Create and manage instance profiles and roles for cluster nodes.

### Route53 Permissions
Manage DNS records and hosted zones (only required if using Route53 DNS provider).

### S3 Permissions
Create and manage S3 buckets for bootstrap ignition configs and registry storage.

### Service Quotas
Read service limits to validate cluster capacity before deployment.

### Resource Tagging
Tag AWS resources for cost tracking and resource management.

## Security Best Practices

1. **Principle of Least Privilege**: Use this policy only for installation/destruction operations
2. **Temporary Credentials**: Consider using AWS STS for time-limited credentials
3. **Separate Accounts**: Use dedicated AWS accounts for OpenShift clusters when possible
4. **Audit Logging**: Enable CloudTrail to monitor installer actions
5. **Credential Rotation**: Rotate access keys regularly (every 90 days recommended)

## Cost Considerations

Resources created by the installer with this policy will incur AWS charges:
- EC2 instances (control plane and worker nodes)
- EBS volumes
- Load balancers (Network Load Balancers)
- NAT Gateways (if using private subnets)
- Data transfer charges
- Route53 hosted zones and queries (if applicable)

See the main README for detailed cost projections.

## Troubleshooting

If installation fails with permission errors:

1. Verify the policy is attached correctly:
   ```bash
   aws iam list-user-policies --user-name openshift-installer
   ```

2. Check AWS service quotas:
   ```bash
   aws service-quotas list-service-quotas --service-code ec2
   ```

3. Ensure your AWS region supports all required services

4. Review CloudTrail logs for specific denied actions

## Related Documentation

- [OpenShift AWS Installation Documentation](https://docs.openshift.com/container-platform/latest/installing/installing_aws/installing-aws-default.html)
- [AWS IAM Best Practices](https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html)
