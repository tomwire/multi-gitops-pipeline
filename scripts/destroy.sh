#!/bin/bash
# =============================================================================
# Destroy script — tears down infrastructure for a given environment
# =============================================================================
set -euo pipefail

ENV="${1:-dev}"

if [[ ! "$ENV" =~ ^(dev|staging|prod)$ ]]; then
  echo "Usage: ./scripts/destroy.sh <dev|staging|prod>"
  exit 1
fi

echo ""
read -p "Type '${ENV}' to confirm destruction of ALL resources: " confirm
if [[ "$confirm" != "${ENV}" ]]; then
  echo "Aborted."
  exit 0
fi

echo ""
echo "Destroying ${ENV} environment..."
cd environments/${ENV}
terraform init \
  -backend-config="bucket=multi-gitops-pipeline-state-us-east-2-${ENV}" \
  -backend-config="key=${ENV}/terraform.tfstate" \
  -backend-config="region=us-east-2"

terraform destroy -auto-approve

echo "✅ ${ENV} destroyed."
