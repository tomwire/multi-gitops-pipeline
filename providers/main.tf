# =============================================================================
# Providers — ECR repository, IAM roles, and ArgoCD service account
# =============================================================================

resource "aws_ecr_repository" "order_service_api" {
  name                 = "order-service-api"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Environment = var.environment
    Project     = "multi-gitops-pipeline"
    ManagedBy   = "terraform"
    CostCenter  = var.cost_center
  }
}

# ---------------------------------------------------------------------------
# ECR Lifecycle Policy — auto-expire old images (keep last N)
# ---------------------------------------------------------------------------
resource "aws_ecr_lifecycle_policy" "order_service_api" {
  repository = aws_ecr_repository.order_service_api.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 30 images per tag pattern"
        selection = {
          tagStatus   = "tagged"
          tagPrefixList = ["v", "latest"]
          countType   = "imageCountMoreThan"
          countNumber = 30
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

# ---------------------------------------------------------------------------
# EKS IAM role for ArgoCD (read-only from ECR, deploy to cluster)
# ---------------------------------------------------------------------------
resource "aws_iam_role" "argocd_ecr_access" {
  name = "argocd-ecr-access-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Principal = {
          Federated = var.eks_oidc_arn
        }
        Condition = {
          StringEquals = {
            "${replace(var.eks_oidc_url, "https://", "")}:sub" = "system:serviceaccount:argocd:argocd-application-controller"
          }
        }
      }
    ]
  })

  tags = {
    Environment = var.environment
    Project     = "multi-gitops-pipeline"
    ManagedBy   = "terraform"
  }
}

resource "aws_iam_role_policy_attachment" "argocd_ecr_read" {
  role       = aws_iam_role.argocd_ecr_access.name
  policy_arn = aws_iam_policy.ecr_pull_only.arn
}

resource "aws_iam_policy" "ecr_pull_only" {
  name        = "ecr-pull-only-${var.environment}"
  description = "Read-only ECR access for ArgoCD"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability"
        ]
        Resource = aws_ecr_repository.order_service_api.arn
      }
    ]
  })
}

# ---------------------------------------------------------------------------
# Output the ECR repo URI for CI workflows
# ---------------------------------------------------------------------------
output "ecr_repository_uri" {
  value       = aws_ecr_repository.order_service_api.repository_url
  description = "ECR repository URI for pushing images"
}

output "ecr_repository_name" {
  value       = aws_ecr_repository.order_service_api.name
  description = "ECR repository name"
}
