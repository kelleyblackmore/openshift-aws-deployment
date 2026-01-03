.PHONY: help setup check-env download-installer validate-config dry-run show-manifests create-cluster destroy-cluster teardown teardown-force clean check-credentials check-secrets test-download

# Default target
.DEFAULT_GOAL := help

# Variables
CLUSTER_NAME ?= my-openshift-cluster
AWS_REGION ?= us-east-1
DNS_PROVIDER ?= route53
HOSTED_ZONE_ID ?=
HOSTED_ZONE_NAME ?=
BASE_DOMAIN ?= example.com
WORKER_AMI ?=
CONTROL_AMI ?=
WORKER_REPLICAS ?= 3
CONTROL_REPLICAS ?= 3
WORKER_INSTANCE_TYPE ?= m5.xlarge
CONTROL_INSTANCE_TYPE ?= m5.xlarge
OPENSHIFT_VERSION ?= latest

# Colors for output
RED := \033[0;31m
GREEN := \033[0;32m
YELLOW := \033[0;33m
BLUE := \033[0;34m
NC := \033[0m # No Color

help: ## Show this help message
	@echo "$(BLUE)OpenShift AWS Deployment Makefile$(NC)"
	@echo ""
	@echo "$(GREEN)Available targets:$(NC)"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(YELLOW)%-25s$(NC) %s\n", $$1, $$2}'
	@echo ""
	@echo "$(GREEN)Configuration:$(NC)"
	@echo "  CLUSTER_NAME=$(CLUSTER_NAME)"
	@echo "  AWS_REGION=$(AWS_REGION)"
	@echo "  DNS_PROVIDER=$(DNS_PROVIDER)"
	@echo "  BASE_DOMAIN=$(BASE_DOMAIN)"
	@echo "  OPENSHIFT_VERSION=$(OPENSHIFT_VERSION)"
	@echo ""
	@echo "$(GREEN)Example usage:$(NC)"
	@echo "  make setup"
	@echo "  make CLUSTER_NAME=prod-cluster AWS_REGION=us-west-2 create-cluster"
	@echo ""
	@echo "$(GREEN)Dry-run workflow:$(NC)"
	@echo "  make validate-config    # Generate install-config.yaml"
	@echo "  make dry-run            # Generate manifests without deploying"
	@echo "  make show-manifests     # Review generated manifests"
	@echo "  make create-cluster     # Deploy if satisfied"
	@echo ""
	@echo "$(RED)Security:$(NC)"
	@echo "  make audit-secrets      # Check for potential secret leaks"
	@echo "  See SECURITY.md for secrets management guidelines"

setup: check-env download-installer ## Complete setup: check dependencies and download installer
	@echo "$(GREEN)✓ Setup complete!$(NC)"
	@echo "$(BLUE)Next steps:$(NC)"
	@echo "  1. Run: make setup-ssh-key (generates and uploads SSH key to AWS)"
	@echo "  2. Set required secret: OPENSHIFT_PULL_SECRET"
	@echo "  3. Run: make validate-config"
	@echo "  4. Run: make create-cluster"

setup-test: check-env check-credentials setup-ssh-key download-installer ## Quick setup for testing (auto-generates SSH key)
	@echo "$(GREEN)✓ Test setup complete!$(NC)"
	@echo "$(BLUE)Next steps:$(NC)"
	@echo "  1. Export SSH key: export SSH_PUBLIC_KEY=\$$(cat ~/.ssh/openshift-cluster.pub)"
	@echo "  2. Set OPENSHIFT_PULL_SECRET from https://console.redhat.com/openshift/install/pull-secret"
	@echo "  3. Run: make validate-config CLUSTER_NAME=test-cluster BASE_DOMAIN=example.com"
	@echo "  4. Run: make create-cluster"

check-env: ## Check if required tools are installed
	@echo "$(BLUE)Checking required dependencies...$(NC)"
	@command -v curl >/dev/null 2>&1 || { echo "$(RED)✗ curl is not installed$(NC)"; exit 1; }
	@echo "$(GREEN)✓ curl$(NC)"
	@command -v jq >/dev/null 2>&1 || { echo "$(RED)✗ jq is not installed$(NC)"; exit 1; }
	@echo "$(GREEN)✓ jq$(NC)"
	@command -v aws >/dev/null 2>&1 || { echo "$(YELLOW)⚠ aws CLI is not installed. Run 'make install-aws-cli' to install it$(NC)"; }
	@command -v aws >/dev/null 2>&1 && echo "$(GREEN)✓ aws CLI$(NC)" || true
	@command -v envsubst >/dev/null 2>&1 || { echo "$(RED)✗ envsubst is not installed$(NC)"; exit 1; }
	@echo "$(GREEN)✓ envsubst$(NC)"
	@command -v tar >/dev/null 2>&1 || { echo "$(RED)✗ tar is not installed$(NC)"; exit 1; }
	@echo "$(GREEN)✓ tar$(NC)"
	@command -v aws >/dev/null 2>&1 && echo "$(GREEN)✓ All required tools are installed$(NC)" || echo "$(YELLOW)⚠ Some tools are missing$(NC)"

check-credentials: ## Verify AWS credentials are configured
	@echo "$(BLUE)Checking AWS credentials...$(NC)"
	@if [ -n "$$AWS_ACCESS_KEY" ] && [ -z "$$AWS_ACCESS_KEY_ID" ]; then \
		export AWS_ACCESS_KEY_ID="$$AWS_ACCESS_KEY"; \
		echo "$(YELLOW)⚠ Mapped AWS_ACCESS_KEY to AWS_ACCESS_KEY_ID$(NC)"; \
	fi
	@if [ -n "$$AWS_SECRET_ACCESS_KEY" ] && [ -z "$$AWS_SECRET_ACCESS_KEY" ]; then \
		echo "$(YELLOW)⚠ Using AWS_SECRET_ACCESS_KEY$(NC)"; \
	fi
	@AWS_ACCESS_KEY_ID=$${AWS_ACCESS_KEY_ID:-$$AWS_ACCESS_KEY} aws sts get-caller-identity >/dev/null 2>&1 || { echo "$(RED)✗ AWS credentials not configured or invalid$(NC)"; exit 1; }
	@echo "$(GREEN)✓ AWS credentials are valid$(NC)"
	@AWS_ACCESS_KEY_ID=$${AWS_ACCESS_KEY_ID:-$$AWS_ACCESS_KEY} aws sts get-caller-identity --query 'Account' --output text | xargs -I {} echo "$(BLUE)  Account ID: {}$(NC)"

check-secrets: ## Verify required secrets are set
	@echo "$(BLUE)Checking required secrets...$(NC)"
	@test -n "$$OPENSHIFT_PULL_SECRET" || { echo "$(RED)✗ OPENSHIFT_PULL_SECRET is not set$(NC)"; exit 1; }
	@echo "$(GREEN)✓ OPENSHIFT_PULL_SECRET$(NC)"
	@test -n "$$SSH_PUBLIC_KEY" || { echo "$(RED)✗ SSH_PUBLIC_KEY is not set$(NC)"; exit 1; }
	@echo "$(GREEN)✓ SSH_PUBLIC_KEY$(NC)"

setup-ssh-key: check-credentials ## Generate SSH key and upload to AWS
	@echo "$(BLUE)Setting up SSH key...$(NC)"
	@CLUSTER_NAME=$(CLUSTER_NAME) AWS_REGION=$(AWS_REGION) AWS_ACCESS_KEY_ID=$${AWS_ACCESS_KEY_ID:-$$AWS_ACCESS_KEY} bash ./scripts/setup-ssh-key.sh
	@echo "$(GREEN)✓ SSH key setup complete$(NC)"
	@echo "$(YELLOW)⚠ Run this to export the key: export SSH_PUBLIC_KEY=\$$(cat ~/.ssh/openshift-cluster.pub)$(NC)"

download-installer: ## Download the OpenShift installer binary
	@echo "$(BLUE)Downloading OpenShift installer (version: $(OPENSHIFT_VERSION))...$(NC)"
	@OPENSHIFT_VERSION=$(OPENSHIFT_VERSION) bash ./openshift/install-scripts/download-installer.sh
	@echo "$(GREEN)✓ Installer downloaded$(NC)"

test-download: check-env ## Test the installer download without keeping it
	@echo "$(BLUE)Testing installer download...$(NC)"
	@OPENSHIFT_VERSION=$(OPENSHIFT_VERSION) bash ./openshift/install-scripts/download-installer.sh
	@./openshift-install version
	@echo "$(GREEN)✓ Download test successful$(NC)"

validate-config: check-secrets ## Validate configuration and generate install-config.yaml
	@echo "$(BLUE)Validating configuration...$(NC)"
	@test -n "$(CLUSTER_NAME)" || { echo "$(RED)✗ CLUSTER_NAME is required$(NC)"; exit 1; }
	@test -n "$(AWS_REGION)" || { echo "$(RED)✗ AWS_REGION is required$(NC)"; exit 1; }
	@test -n "$(DNS_PROVIDER)" || { echo "$(RED)✗ DNS_PROVIDER is required$(NC)"; exit 1; }
	@if [ "$(DNS_PROVIDER)" = "route53" ]; then \
		test -n "$(HOSTED_ZONE_ID)" || { echo "$(RED)✗ HOSTED_ZONE_ID is required for route53$(NC)"; exit 1; }; \
		test -n "$(HOSTED_ZONE_NAME)" || { echo "$(RED)✗ HOSTED_ZONE_NAME is required for route53$(NC)"; exit 1; }; \
	fi
	@echo "$(GREEN)✓ Configuration is valid$(NC)"
	@echo "$(BLUE)Generating install-config.yaml...$(NC)"
	@export CLUSTER_NAME=$(CLUSTER_NAME) \
		AWS_REGION=$(AWS_REGION) \
		DNS_PROVIDER=$(DNS_PROVIDER) \
		HOSTED_ZONE_ID=$(HOSTED_ZONE_ID) \
		HOSTED_ZONE_NAME=$(HOSTED_ZONE_NAME) \
		BASE_DOMAIN=$(BASE_DOMAIN) \
		WORKER_AMI=$(WORKER_AMI) \
		CONTROL_AMI=$(CONTROL_AMI) \
		WORKER_REPLICAS=$(WORKER_REPLICAS) \
		CONTROL_REPLICAS=$(CONTROL_REPLICAS) \
		WORKER_INSTANCE_TYPE=$(WORKER_INSTANCE_TYPE) \
		CONTROL_INSTANCE_TYPE=$(CONTROL_INSTANCE_TYPE) && \
	bash ./scripts/prepare-config.sh \
		--cluster-name $(CLUSTER_NAME) \
		--region $(AWS_REGION) \
		--dns-provider $(DNS_PROVIDER) \
		--hosted-zone-id "$(HOSTED_ZONE_ID)" \
		--hosted-zone-name "$(HOSTED_ZONE_NAME)" \
		--worker-ami "$(WORKER_AMI)" \
		--control-ami "$(CONTROL_AMI)"
	@echo "$(GREEN)✓ install-config.yaml created at ./cluster-output/install-config.yaml$(NC)"

show-config: ## Display the generated install-config.yaml
	@if [ ! -f ./cluster-output/install-config.yaml ]; then \
		echo "$(RED)✗ No install-config.yaml found. Run 'make validate-config' first$(NC)"; \
		exit 1; \
	fi
	@echo "$(BLUE)Current install-config.yaml:$(NC)"
	@cat ./cluster-output/install-config.yaml

dry-run: validate-config ## Generate manifests without creating cluster (dry-run)
	@echo "$(BLUE)Generating manifests (dry-run mode)...$(NC)"
	@test -f ./openshift-install || { echo "$(RED)✗ openshift-install not found. Run 'make download-installer' first$(NC)"; exit 1; }
	@echo "$(YELLOW)Creating install-config backup...$(NC)"
	@cp ./cluster-output/install-config.yaml ./cluster-output/install-config.yaml.backup
	@echo "$(BLUE)Generating Kubernetes manifests...$(NC)"
	./openshift-install create manifests --dir=./cluster-output --log-level=info
	@echo ""
	@echo "$(GREEN)✓ Dry-run complete! Manifests generated.$(NC)"
	@echo ""
	@echo "$(BLUE)Generated manifests are in:$(NC) ./cluster-output/manifests/"
	@echo "$(BLUE)Machine configs are in:$(NC) ./cluster-output/openshift/"
	@echo ""
	@echo "$(YELLOW)Note:$(NC) The install-config.yaml was consumed. Backup saved as install-config.yaml.backup"
	@echo ""
	@echo "$(BLUE)To review manifests:$(NC)"
	@echo "  ls -la ./cluster-output/manifests/"
	@echo "  ls -la ./cluster-output/openshift/"
	@echo ""
	@echo "$(BLUE)To proceed with cluster creation:$(NC)"
	@echo "  make create-cluster"

show-manifests: ## Display generated manifests (after dry-run)
	@if [ ! -d ./cluster-output/manifests ]; then \
		echo "$(RED)✗ No manifests found. Run 'make dry-run' first$(NC)"; \
		exit 1; \
	fi
	@echo "$(BLUE)Generated Manifests:$(NC)"
	@echo ""
	@echo "$(YELLOW)Manifest files:$(NC)"
	@ls -1 ./cluster-output/manifests/ | sed 's/^/  /'
	@echo ""
	@echo "$(YELLOW)OpenShift configs:$(NC)"
	@ls -1 ./cluster-output/openshift/ | sed 's/^/  /'
	@echo ""
	@echo "$(BLUE)To view a specific manifest:$(NC)"
	@echo "  cat ./cluster-output/manifests/<filename>"

estimate-cost: ## Show estimated AWS costs
	@echo "$(BLUE)Estimated Monthly AWS Costs:$(NC)"
	@echo ""
	@echo "$(YELLOW)Compute Instances:$(NC)"
	@echo "  Control Plane ($(CONTROL_REPLICAS)x $(CONTROL_INSTANCE_TYPE)): ~\$$414/month"
	@echo "  Worker Nodes ($(WORKER_REPLICAS)x $(WORKER_INSTANCE_TYPE)): ~\$$414/month"
	@echo ""
	@echo "$(YELLOW)Storage (EBS):$(NC)"
	@echo "  ~720 GB gp3 volumes: ~\$$58/month"
	@echo ""
	@echo "$(YELLOW)Load Balancers:$(NC)"
	@echo "  2x Network Load Balancers: ~\$$32/month"
	@echo ""
	@echo "$(YELLOW)Networking:$(NC)"
	@echo "  NAT Gateways (3 AZs): ~\$$96/month"
	@echo "  Route53 (if used): ~\$$0.50/month"
	@echo ""
	@echo "$(GREEN)Total Estimated: ~\$$1,050-1,200/month$(NC)"
	@echo ""
	@echo "$(BLUE)Cost optimization options:$(NC)"
	@echo "  - Use m5.large instances: saves ~50%"
	@echo "  - Reduce worker count to 2: saves ~\$$138/month"
	@echo "  - Use Reserved Instances: saves 30-50%"

create-cluster: check-credentials validate-config ## Create the OpenShift cluster
	@echo "$(BLUE)Creating OpenShift cluster...$(NC)"
	@echo "$(YELLOW)This will take approximately 30-45 minutes$(NC)"
	@test -f ./openshift-install || { echo "$(RED)✗ openshift-install not found. Run 'make download-installer' first$(NC)"; exit 1; }
	@export AWS_ACCESS_KEY_ID=$${AWS_ACCESS_KEY_ID:-$$AWS_ACCESS_KEY} && \
	export AWS_SECRET_ACCESS_KEY=$${AWS_SECRET_ACCESS_KEY} && \
	export AWS_DEFAULT_REGION=$(AWS_REGION) && \
	./openshift-install create cluster --dir=./cluster-output --log-level=info
	@echo "$(GREEN)✓ Cluster created successfully!$(NC)"
	@echo ""
	@echo "$(BLUE)Kubeconfig location:$(NC) ./cluster-output/auth/kubeconfig"
	@echo "$(BLUE)Access the cluster:$(NC) export KUBECONFIG=./cluster-output/auth/kubeconfig"
	@make handle-dns

handle-dns: ## Handle DNS records after cluster creation
	@if [ ! -d ./cluster-output ]; then \
		echo "$(RED)✗ cluster-output directory not found$(NC)"; \
		exit 1; \
	fi
	@echo "$(BLUE)Processing DNS records...$(NC)"
	@export AWS_ACCESS_KEY_ID=$${AWS_ACCESS_KEY_ID:-$$AWS_ACCESS_KEY} && \
	export AWS_SECRET_ACCESS_KEY=$${AWS_SECRET_ACCESS_KEY} && \
	export DNS_PROVIDER=$(DNS_PROVIDER) \
		HOSTED_ZONE_ID=$(HOSTED_ZONE_ID) && \
	bash ./scripts/handle-dns-output.sh ./cluster-output

destroy-cluster: ## Destroy the OpenShift cluster
	@echo "$(RED)WARNING: This will destroy the cluster and all associated resources!$(NC)"
	@echo -n "Are you sure? [y/N] " && read ans && [ $${ans:-N} = y ]
	@test -f ./openshift-install || { echo "$(RED)✗ openshift-install not found. Run 'make download-installer' first$(NC)"; exit 1; }
	@test -d ./cluster-output || { echo "$(RED)✗ cluster-output directory not found$(NC)"; exit 1; }
	@echo "$(BLUE)Destroying cluster...$(NC)"
	@export AWS_ACCESS_KEY_ID=$${AWS_ACCESS_KEY_ID:-$$AWS_ACCESS_KEY} && \
	export AWS_SECRET_ACCESS_KEY=$${AWS_SECRET_ACCESS_KEY} && \
	export AWS_DEFAULT_REGION=$(AWS_REGION) && \
	./openshift-install destroy cluster --dir=./cluster-output --log-level=info
	@echo "$(GREEN)✓ Cluster destroyed$(NC)"

teardown: ## Complete teardown (cluster + AWS resources + local artifacts)
	@CLUSTER_NAME=$(CLUSTER_NAME) AWS_REGION=$(AWS_REGION) AWS_ACCESS_KEY_ID=$${AWS_ACCESS_KEY_ID:-$$AWS_ACCESS_KEY} bash ./scripts/teardown.sh

teardown-force: ## Complete teardown without confirmation prompts
	@CLUSTER_NAME=$(CLUSTER_NAME) AWS_REGION=$(AWS_REGION) AWS_ACCESS_KEY_ID=$${AWS_ACCESS_KEY_ID:-$$AWS_ACCESS_KEY} SKIP_CONFIRMATION=true bash ./scripts/teardown.sh

backup-config: ## Backup cluster configuration and credentials
	@test -d ./cluster-output || { echo "$(RED)✗ cluster-output directory not found$(NC)"; exit 1; }
	@BACKUP_DIR="./backups/$(CLUSTER_NAME)-$$(date +%Y%m%d-%H%M%S)" && \
	mkdir -p $$BACKUP_DIR && \
	cp -r ./cluster-output/auth $$BACKUP_DIR/ && \
	cp ./cluster-output/metadata.json $$BACKUP_DIR/ 2>/dev/null || true && \
	cp ./cluster-output/install-config.yaml $$BACKUP_DIR/ 2>/dev/null || true && \
	echo "$(GREEN)✓ Backup created at $$BACKUP_DIR$(NC)"

clean: ## Clean up temporary files and installer binary
	@echo "$(BLUE)Cleaning up...$(NC)"
	@rm -f ./openshift-install
	@rm -rf ./cluster-output
	@rm -rf ./ami-artifact
	@echo "$(GREEN)✓ Cleanup complete$(NC)"
	@echo "$(YELLOW)Note: Secrets in cluster-output/ have been removed$(NC)"

clean-all: clean ## Clean everything including backups
	@echo "$(YELLOW)Removing all backups...$(NC)"
	@rm -rf ./backups
	@echo "$(GREEN)✓ All cleaned$(NC)"

install-aws-cli: ## Install AWS CLI v2
	@echo "$(BLUE)Installing AWS CLI v2...$(NC)"
	@if command -v aws >/dev/null 2>&1; then \
		echo "$(GREEN)✓ AWS CLI is already installed$(NC)"; \
		aws --version; \
		exit 0; \
	fi
	@echo "$(YELLOW)Detecting operating system...$(NC)"
	@if [ "$$(uname)" = "Linux" ]; then \
		echo "$(BLUE)Installing AWS CLI for Linux...$(NC)"; \
		cd /tmp && \
		curl -sSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" && \
		unzip -q awscliv2.zip && \
		sudo ./aws/install --update && \
		rm -rf aws awscliv2.zip && \
		echo "$(GREEN)✓ AWS CLI installed successfully$(NC)"; \
	elif [ "$$(uname)" = "Darwin" ]; then \
		echo "$(BLUE)Installing AWS CLI for macOS...$(NC)"; \
		cd /tmp && \
		curl -sSL "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o "AWSCLIV2.pkg" && \
		sudo installer -pkg AWSCLIV2.pkg -target / && \
		rm -f AWSCLIV2.pkg && \
		echo "$(GREEN)✓ AWS CLI installed successfully$(NC)"; \
	else \
		echo "$(RED)✗ Unsupported operating system: $$(uname)$(NC)"; \
		exit 1; \
	fi
	@aws --version

install-deps-ubuntu: ## Install dependencies on Ubuntu/Debian
	@echo "$(BLUE)Installing dependencies for Ubuntu/Debian...$(NC)"
	sudo apt-get update
	sudo apt-get install -y curl jq gettext-base unzip
	@make install-aws-cli
	@echo "$(GREEN)✓ All dependencies installed$(NC)"

install-deps-macos: ## Install dependencies on macOS
	@echo "$(BLUE)Installing dependencies for macOS...$(NC)"
	@command -v brew >/dev/null 2>&1 || { echo "$(RED)✗ Homebrew is not installed. Install from https://brew.sh$(NC)"; exit 1; }
	brew install curl jq gettext
	@make install-aws-cli
	@echo "$(GREEN)✓ All dependencies installed$(NC)"

iam-setup: ## Display IAM setup instructions
	@echo "$(BLUE)IAM Setup Instructions:$(NC)"
	@echo ""
	@echo "$(YELLOW)Create IAM user:$(NC)"
	@echo "  aws iam create-user --user-name openshift-installer"
	@echo ""
	@echo "$(YELLOW)Attach policy:$(NC)"
	@echo "  aws iam put-user-policy \\"
	@echo "    --user-name openshift-installer \\"
	@echo "    --policy-name OpenShiftInstallerPolicy \\"
	@echo "    --policy-document file://docs/aws-iam-policy.json"
	@echo ""
	@echo "$(YELLOW)Create access keys:$(NC)"
	@echo "  aws iam create-access-key --user-name openshift-installer"
	@echo ""
	@echo "$(BLUE)See docs/README-IAM.md for more details$(NC)"

status: ## Show cluster status
	@if [ ! -f ./cluster-output/auth/kubeconfig ]; then \
		echo "$(RED)✗ Kubeconfig not found. Cluster may not be created yet.$(NC)"; \
		exit 1; \
	fi
	@echo "$(BLUE)Cluster Status:$(NC)"
	@export KUBECONFIG=./cluster-output/auth/kubeconfig && \
	kubectl cluster-info && \
	echo "" && \
	echo "$(BLUE)Nodes:$(NC)" && \
	kubectl get nodes && \
	echo "" && \
	echo "$(BLUE)Cluster Operators:$(NC)" && \
	kubectl get clusteroperators

logs: ## Show recent installer logs (redacted)
	@if [ -f ./cluster-output/.openshift_install.log ]; then \
		tail -n 50 ./cluster-output/.openshift_install.log | sed 's/pullSecret.*/pullSecret: [REDACTED]/g' | sed 's/sshKey.*/sshKey: [REDACTED]/g'; \
	else \
		echo "$(RED)✗ No installer logs found$(NC)"; \
	fi

audit-secrets: ## Check for potential secret leaks in tracked files
	@echo "$(BLUE)Scanning for potential secrets...$(NC)"
	@if git rev-parse --git-dir > /dev/null 2>&1; then \
		echo "$(YELLOW)Checking staged files:$(NC)"; \
		git diff --cached --name-only | xargs -I {} sh -c 'echo "  Checking: {}" && grep -n -E "AKIA|aws_access_key|aws_secret|pullSecret.*auths|BEGIN.*PRIVATE KEY" {} 2>/dev/null && echo "$(RED)  ⚠ Potential secret found in {}$(NC)" || true'; \
		echo "$(YELLOW)Checking tracked files for common patterns:$(NC)"; \
		git ls-files | grep -E "\.(sh|yaml|yml|json|env)$$" | xargs grep -l -E "password.*=|secret.*=|token.*=|key.*=" 2>/dev/null | while read file; do \
			if ! grep -q "$$file" .gitignore 2>/dev/null; then \
				echo "$(YELLOW)  ⚠ Review: $$file$(NC)"; \
			fi; \
		done; \
		echo "$(GREEN)✓ Audit complete$(NC)"; \
	else \
		echo "$(RED)✗ Not a git repository$(NC)"; \
	fi

quick-test: ## Quick test setup (automated SSH key + config generation)
	@bash ./scripts/quick-test-setup.sh

quick-start: setup validate-config estimate-cost ## Quick start guide
	@echo ""
	@echo "$(GREEN)========================================$(NC)"
	@echo "$(GREEN)  Ready to create your cluster!$(NC)"
	@echo "$(GREEN)========================================$(NC)"
	@echo ""
	@echo "$(BLUE)Run the following command to create the cluster:$(NC)"
	@echo "  make create-cluster"
	@echo ""
	@echo "$(YELLOW)Or customize with environment variables:$(NC)"
	@echo "  make CLUSTER_NAME=prod AWS_REGION=us-west-2 create-cluster"
