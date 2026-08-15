# =============================================================================
# Dev Environment — Entry point
# =============================================================================

terraform {
  backend "s3" {
    bucket         = "multi-gitops-pipeline-state-us-east-2-dev"
    key            = "dev/terraform.tfstate"
    region         = "us-east-2"
    encrypt        = true
    # S3 object locking handles state protection (Terraform 1.13+)
  }
}

provider "aws" {
  region = var.region
}

module "providers" {
  source = "../../providers"

  environment   = "dev"
  cost_center   = "development"
  eks_cluster_name = var.eks_cluster_name
  eks_oidc_arn     = var.eks_oidc_arn
  eks_oidc_url     = var.eks_oidc_url
  subnet_ids       = var.subnet_ids
}
