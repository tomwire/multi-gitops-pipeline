#!/bin/bash
# =============================================================================
# Setup script — provisions ECR repository and IAM roles for a given environment
# =============================================================================
set -euo pipefail

ENV="${1:-dev}"

if [[ ! "$ENV" =~ ^(dev|staging|prod)$ ]]; then
  echo "Usage: ./scripts/setup.sh <dev|staging|prod>"
  exit 1
fi

echo "=============================================="
echo " Setting up GitOps pipeline for ${ENV}"
echo "=============================================="

# Verify prerequisites
for cmd in terraform aws kubectl; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "❌ $cmd not found — install it first"; exit 1; }
done

echo ""
echo "Step 1/3: Initialize Terraform..."
cd environments/${ENV}
terraform init \
  -backend-config="bucket=multi-gitops-pipeline-state-us-east-2-${ENV}" \
  -backend-config="key=${ENV}/terraform.tfstate" \
  -backend-config="region=us-east-2"

echo ""
echo "Step 2/3: Plan infrastructure changes..."
terraform plan -out=tfplan

echo ""
read -p "Apply Terraform for ${ENV}? [y/N] " confirm
if [[ "$confirm" != "y" ]]; then
  echo "Aborted."
  exit 0
fi

echo ""
echo "Step 3/3: Apply..."
terraform apply tfplan

echo ""
echo "=============================================="
echo " ✅ ${ENV} environment provisioned!"
echo "=============================================="
echo ""
echo "ECR Repository: $(terraform output -raw ecr_repository_name)"
echo ""
echo "Next steps:"
echo "  1. Push your first image (CI pipeline or manually):"
echo "     docker build -t ECR_URI/order-service-api:latest . && docker push ..."
echo ""
echo "  2. Deploy ArgoCD applications:"
echo "     kubectl apply -f k8s-manifests/argocd/applications.yaml"
echo ""
echo "  3. Run 'make deploy ENV=${ENV}' for the full workflow"
