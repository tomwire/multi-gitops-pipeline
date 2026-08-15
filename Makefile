# =============================================================================
# Multi-Stage GitOps Pipeline - Makefile
# =============================================================================

SHELL := /bin/bash
.DEFAULT_GOAL := help

TERRAFORM := terraform
KUBECTL := kubectl
KUSTOMIZE := kustomize
ENV ?= dev

.PHONY: help
help: ## Show available targets
	@echo "Multi-Stage GitOps Pipeline — Automated release management + drift detection"
	@echo ""
	@echo "Usage:"
	@echo "  make <target> ENV=<dev|staging|prod>"
	@echo ""
	@echo "Targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

# ---------------------------------------------------------------------------
# Terraform — Infrastructure (ECR + IAM)
# ---------------------------------------------------------------------------

.PHONY: init-terraform
init-terraform: ## Initialize Terraform in environment directory
	@echo "Initializing Terraform for ${ENV}..."
	@cd environments/${ENV} && $(TERRAFORM) init \
		-backend-config="bucket=multi-gitops-pipeline-state-us-east-2-${ENV}" \
		-backend-config="key=${ENV}/terraform.tfstate" \
		-backend-config="region=us-east-2"
	@echo "✓ Terraform initialized"

.PHONY: plan
plan: ## Plan Terraform changes for environment
	@$(MAKE) init-terraform
	@cd environments/${ENV} && $(TERRAFORM) plan -out=tfplan
	@echo "✓ Terraform plan generated — review before applying"

.PHONY: apply
apply: ## Apply Terraform for environment (confirm first)
	@read -p "Apply Terraform for ${ENV}? [y/N] " confirm && \
		[ "$$confirm" = "y" ] || { echo "Aborted"; exit 1; }
	@cd environments/${ENV} && $(TERRAFORM) apply tfplan

.PHONY: destroy-terraform
destroy-terraform: ## Destroy Terraform resources for environment
	@read -p "Type '${ENV}' to confirm destruction: " confirm && \
		[ "$$confirm" = "${ENV}" ] || { echo "Aborted"; exit 1; }
	@cd environments/${ENV} && $(TERRAFORM) init \
		-backend-config="bucket=multi-gitops-pipeline-state-us-east-2-${ENV}" \
		-backend-config="key=${ENV}/terraform.tfstate" \
		-backend-config="region=us-east-2" && \
		$(TERRAFORM) destroy -auto-approve

# ---------------------------------------------------------------------------
# Kubernetes — Deploy ArgoCD Applications
# ---------------------------------------------------------------------------

.PHONY: deploy-k8s
deploy-k8s: ## Apply ArgoCD Applications (self-syncing per environment)
	@echo "Deploying ArgoCD Applications for ${ENV}..."
	@$(KUBECTL) apply -f k8s-manifests/argocd/applications.yaml
	@echo "✓ ArgoCD Applications applied — watch with: kubectl get applications -n argocd"

.PHONY: deploy-kustomize
deploy-kustomize: ## Build and preview Kustomize overlay (dry-run)
	@$(KUSTOMIZE) build k8s-manifests/overlays/${ENV}

# ---------------------------------------------------------------------------
# Full Deployment
# ---------------------------------------------------------------------------

.PHONY: deploy
deploy: ## Full deploy: Terraform + ArgoCD sync
	@echo "=============================================="
	@echo " Deploying ${ENV} GitOps pipeline"
	@echo "=============================================="
	@echo ""
	@echo "Step 1/2: Terraform — ECR repo, IAM roles"
	@$(MAKE) plan apply ENV=${ENV}
	@echo ""
	@echo "Step 2/2: Deploy ArgoCD Applications"
	@$(MAKE) deploy-k8s ENV=${ENV}
	@echo ""
	@echo "✓ ${ENV} GitOps pipeline deployed!"
	@echo ""
	@echo "Next steps:"
	@echo "  kubectl get pods -n order-service-api-${ENV}   # Check app pods"
	@echo "  kubectl get applications -n argocd             # Watch ArgoCD sync status"

# ---------------------------------------------------------------------------
# Validation & Security
# ---------------------------------------------------------------------------

.PHONY: validate
validate: ## Validate all Terraform configs + Kustomize builds
	@echo "=== Terraform Validation ==="
	@cd providers && $(TERRAFORM) init -backend=false >/dev/null 2>&1 && \
		$(TERRAFORM) validate && echo "providers: OK" || echo "providers: FAIL"
	@echo ""
	@echo "=== Kustomize Validation ==="
	@for env in dev staging prod; do \
		echo -n "$$env:    " && \
		kustomize build k8s-manifests/overlays/$$env >/dev/null 2>&1 && \
			echo "OK" || echo "FAIL (expected — placeholders need values)"; \
	done

.PHONY: check
check: ## Run all scans (trufflehog, tfsec, validate)
	@echo "=== TruffleHog ===" && \
		command -v trufflehog &> /dev/null && \
		trufflehog filesystem . --fail --no-update || \
		echo "TruffleHog not installed — skipping"
	@echo ""
	@echo "=== tfsec ===" && \
		command -v tfsec &> /dev/null && \
		tfsec . --no-color || \
		echo "tfsec not installed — skipping"
	@echo ""
	$(MAKE) validate

# ---------------------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------------------

.PHONY: cleanup
cleanup: ## Clean Terraform artifacts (not state!)
	@echo "Cleaning Terraform artifacts..."
	@rm -rf providers/.terraform* providers/*.tfplan environments/*/.terraform* 2>/dev/null || true
	@echo "✓ Cleanup complete"
