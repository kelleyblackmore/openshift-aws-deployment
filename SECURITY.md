# Security Guidelines

## Secrets Management

This repository requires several sensitive credentials to deploy OpenShift clusters. Follow these guidelines to prevent secret leaks.

## Required Secrets

1. `OPENSHIFT_PULL_SECRET` - Red Hat pull secret from console.redhat.com
2. `SSH_PUBLIC_KEY` - SSH public key for cluster access
3. `AWS_ACCESS_KEY` or `AWS_ACCESS_KEY_ID` - AWS access key
4. `AWS_SECRET_ACCESS_KEY` - AWS secret key

## How to Handle Secrets

### DO:
- Use environment variables for all secrets
- Store secrets in CI/CD secret managers (GitHub Secrets, AWS Secrets Manager, etc.)
- Use `.env` files locally (they are gitignored)
- Rotate credentials regularly (every 90 days recommended)
- Use AWS IAM roles with temporary credentials when possible
- Review `git status` before committing

### DO NOT:
- Commit secrets to version control
- Log secret values in scripts (use `echo "SECRET: [REDACTED]"`)
- Share secrets via chat or email
- Store secrets in plaintext files tracked by git
- Use production credentials for testing

## Files That May Contain Secrets

The following files/directories are automatically gitignored but should never be committed:

- `cluster-output/` - Contains install-config.yaml with pull secrets and SSH keys
- `cluster-output/.openshift_install_state.json` - Contains embedded SSH keys
- `cluster-output/install-config.yaml.backup` - Backup containing secrets
- `cluster-output/auth/` - Contains kubeconfig with cluster credentials
- `.env*` files - May contain AWS credentials
- `*.pem`, `*.key`, `id_rsa*` - SSH private keys

## CI/CD Setup

When using GitHub Actions or other CI/CD:

1. **Add secrets to repository/organization settings:**
   - `OPENSHIFT_PULL_SECRET`
   - `SSH_PUBLIC_KEY`
   - `AWS_ACCESS_KEY`
   - `AWS_SECRET_ACCESS_KEY`

2. **Reference secrets in workflows:**
   ```yaml
   env:
     OPENSHIFT_PULL_SECRET: ${{ secrets.OPENSHIFT_PULL_SECRET }}
     SSH_PUBLIC_KEY: ${{ secrets.SSH_PUBLIC_KEY }}
   ```

3. **Never echo secrets in logs:**
   ```bash
   # Good
   echo "Using pull secret from environment"
   
   # Bad
   echo "Pull secret: $OPENSHIFT_PULL_SECRET"
   ```

## Emergency Response

If secrets are accidentally committed:

1. **Rotate all exposed credentials immediately**
2. **Remove from git history:**
   ```bash
   git filter-branch --force --index-filter \
     "git rm --cached --ignore-unmatch <file-with-secret>" \
     --prune-empty --tag-name-filter cat -- --all
   git push origin --force --all
   ```
3. **Notify security team if in organization**
4. **Review access logs for unauthorized usage**

## Auditing

Regular security checks:

```bash
# Check for accidentally staged secrets
git diff --cached | grep -E "SECRET|PASSWORD|KEY|TOKEN"

# Scan for potential secrets in codebase
grep -r "password\|secret\|token" . --exclude-dir=.git

# Verify gitignore is working
git status --ignored
```

## Reporting Security Issues

If you discover a security vulnerability, please email security@example.com instead of opening a public issue.
