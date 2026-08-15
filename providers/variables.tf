# =============================================================================
# Providers — Input variables
# =============================================================================

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

variable "cost_center" {
  description = "Cost center for resource tagging"
  type        = string
  default     = "platform-engineering"
}

variable "eks_cluster_name" {
  description = "EKS cluster name from enterprise-terraform-aws (consumed via cross-repo variable)"
  type        = string
}

variable "eks_oidc_arn" {
  description = "OIDC provider ARN for IRSA (from enterprise-terraform-aws)"
  type        = string
}

variable "eks_oidc_url" {
  description = "OIDC provider URL for IRSA condition matching"
  type        = string
}

variable "subnet_ids" {
  description = "Private subnet IDs for EKS node placement (from enterprise-terraform-aws)"
  type        = list(string)
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-2"
}
