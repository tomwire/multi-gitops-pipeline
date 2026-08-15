# =============================================================================
# Staging Environment — Variables (consumes enterprise-terraform-aws outputs)
# =============================================================================

variable "eks_cluster_name" { description = "EKS cluster name from enterprise-terraform-aws"; type = string }
variable "eks_oidc_arn"    { description = "OIDC provider ARN from enterprise-terraform-aws"; type = string }
variable "eks_oidc_url"    { description = "OIDC provider URL from enterprise-terraform-aws"; type = string }
variable "subnet_ids"      { description = "Private subnet IDs from enterprise-terraform-aws"; type = list(string) }
variable "region"          { description = "AWS region"; type = string; default = "us-east-2" }
