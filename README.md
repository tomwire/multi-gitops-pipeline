# 🔄 Multi-Stage GitOps Pipeline (ArgoCD + Kustomize)

A production-grade, multi-stage delivery pipeline for Amazon EKS — automated image promotion, approval gates, and drift detection. Showcases modern GitOps workflows with ArgoCD self-healing sync and Kustomize environment overlays.

> **Purpose:** Demonstrates enterprise CI/CD pipelines where applications flow through dev → staging → prod with automated promotion to dev, manual approval gates for stage/prod, and scheduled drift detection between Git-defined desired state and live cluster reality. Designed to integrate seamlessly with the [enterprise-terraform-aws](https://github.com/twire/enterprise-terraform-aws) repo which provisions the underlying EKS cluster and S3 state.

[![GitHub Actions](https://img.shields.io/badge/GitHub_Actions-2671E5?style=flat-square&logo=githubactions&logoColor=white)](https://github.com/features/actions)
[![ArgoCD](https://img.shields.io/badge/ArgoCD-EO3EAC?style=flat-square&logo=kubernetes&logoColor=white)](https://argo-cd.readthedocs.io/)
[![Kustomize](https://img.shields.io/badge/Kustomize-673AB8?style=flat-square&logo=kubernetes&logoColor=white)](https://kustomize.io/)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

---

## 📋 Table of Contents

- [Architecture](#-architecture)
- [Promotion Pipeline](#-promotion-pipeline)
- [Components](#-components)
- [Integration with enterprise-terraform-aws](#-integration-with-enterprise-terraform-aws)
- [Environments](#-environments)
- [Project Structure](#-project-structure)
- [Prerequisites](#-prerequisites)
- [Quick Start](#-quick-start)
- [CI Pipeline](#-ci-pipeline)
- [CD Workflows](#-cd-workflows)
- [Drift Detection](#-drift-detection)
- [Key Patterns](#-key-patterns)
- [Cost Estimates](#-cost-estimates)
- [Security](#-security)
- [Destroy](#-destroy)
- [Interview Talking Points](#-interview-talking-points)

---

## 🏗️ Architecture

```
                        ┌──────────────────────────────────────────────────────┐
                        │                  GitHub                              │
                        │                                                      │
                        │  ┌─────────┐  ┌──────────┐  ┌──────────────────┐     │
                        │  │  Code   │→│  CI:      │→│  CD:             │     │
                        │  │ (app +  │ │  Build &  │ │  Promote via     │     │
                        │  │ infra)  │ │  Push to  │ │  Bot Account     │     │
                        │  └─────────┘ │  ECR      │→│  (git commit →   │     │
                        │              │           │ │   ArgoCD sync)    │     │
                        │              └──────┬────┘ └────────┬─────────┘     │
                        │                     │               │                │
                        └─────────────────────┼───────────────┼────────────────┘
                                              │               │
                                      ECR Push        Manifest Update (bot)
                                             │               │
                                     ┌───────▼───────┐  ┌────▼───────┐
                                     │   Amazon ECR   │  │    ArgoCD    │
                                     │                │  │  (on EKS)    │
                                     │ order-service- │  │              │
                                     │ api:latest     │  │  ┌────────┐  │
                                     │ v20260115-abc  │  │  │ Dev    │  │
                                     │ ...            │  │  │ Stage  │  │
                                     └───────┬────────┘  │  │ Prod   │  │
                                             │           │  └────────┘  │
                        ┌────────────────────┼───────────┼─────────────┐
                        │                    │           │             │
                 ┌──────▼──────┐    ┌────────▼────────┐ │             │
                 │  Drift      │    │  Promotion Gate  │ │             │
                 │  Detection  │    │  (staging/prod)  │ │             │
                 │  (cron Job) │    │  Manual approval │ │             │
                 └─────────────┘    └─────────────────┘ │             │
                                                       └─────────────┘
```

### Deployment Topology

Each environment deploys to a **separate Kubernetes namespace** within the same EKS cluster:

| Namespace | ArgoCD Config | Auto-Sync? | Promotion Source |
|-----------|--------------|------------|------------------|
| `order-service-api-dev` | `selfHeal: true` | ✅ Yes | CI pipeline (auto) |
| `order-service-api-staging` | `selfHeal: true` | ⚠️ After approval | Manual merge to main |
| `order-service-api-prod` | `selfHeal: false` | ❌ No — manual gate | Manual workflow dispatch |

---

## 🔄 Promotion Pipeline

The pipeline implements a **three-stage promotion model** where each stage has different trust levels and gates:

```
     Developer          CI System              ArgoCD            Production Cluster
        │                    │                     │                    │
        │ 1. Push code       │                     │                    │
        ├───────────────────►│                     │                    │
        │                    │ 2. Build image       │                    │
        │                    │    → ECR             │                    │
        │                    │ 3. Update dev overlay│                    │
        │                    │    (bot commits)     │                    │
        │                    ├─────────────────────►│                    │
        │                    │                     │ 4. Auto-sync       │
        │                    │                     │    → Dev namespace  │
        │                    │                     │         │          │
        │                    │                     │         ▼          │
        │   5. Manual        │                     │         │          │
        │   promotion to     │                     │         │          │
        │   staging ←───────┘                     │         │          │
        │      (GitHub workflow dispatch)           │         │          │
        │                                           │         ▼          │
        │                                            │    Staging      │
        │                                            │                   │
        │   6. Promote to prod                       │         │          │
        │      (manual + validation gates) ←────────┘         │          │
        │                                           │         ▼          │
        │                                           │    Prod           │
```

---

## 🧩 Components

| Component | Version | Purpose | Namespace |
|-----------|---------|---------|-----------|
| **Order Service API** | Custom Flask app | Demo microservice with Redis caching, health probes, readiness checks | Per-env |
| **Redis** | redis:7-alpine | In-cluster cache (per-environment isolation) | Per-env |
| **ArgoCD Application** | Native K8s CRD | Declarative deployment with auto-sync and self-heal | `argocd` |
| **Kustomize** | v5.4.0 | Environment-specific overlays (base + dev/staging/prod) | N/A |
| **ECR** | Amazon Elastic Container Registry | Container image storage with lifecycle policies | AWS Account |

### Image Lifecycle in ECR

| Tag Pattern | Retention | Promotion Stage |
|-------------|-----------|-----------------|
| `latest` | Always latest 1 image | Dev (auto-pushed by CI) |
| `vYYYYMMDD-SHA` | Last 30 images | Staging / Prod (manual promotion) |
| Lifecycle policy | Max 30 tagged images per pattern | Auto-cleanup on each push |

---

## 🔗 Integration with enterprise-terraform-aws

This repo is a **companion** to [enterprise-terraform-aws](https://github.com/twire/enterprise-terraform-aws):

```
enterprise-terraform-aws          multi-gitops-pipeline
┌─────────────────────┐          ┌──────────────────────────┐
│ VPC + Subnets       │          │ ECR repository + lifecycle│
│ EKS Cluster         │─────────►│ IAM roles (IRSA)         │
│ IRSA / OIDC         │  cluster │ S3 state buckets         │
│ Private subnets     │  name,  │                          │
└─────────────────────┘  OIDC   │ Kustomize overlays        │
              ▲            info  │ ArgoCD Applications       │
              │            for    │ CI/CD workflows           │
              └── Terraform outputs passed as variables ─────┘
```

The pipeline **consumes** cluster infrastructure from `enterprise-terraform-aws` via:
- `eks_cluster_name` — EKS cluster name for kubeconfig
- `eks_oidc_arn` + `eks_oidc_url` — OIDC provider for IRSA role assumption
- `subnet_ids` — Private subnets for any future node additions

This separation keeps each repo focused and independently deployable.

---

## 🌍 Environments

| Environment | Replicas | Resources per Pod | Auto-Sync? | Promotion Gate |
|-------------|----------|-------------------|------------|----------------|
| **dev** | 1 | 50m CPU / 64Mi mem | ✅ Immediate | None (auto from CI) |
| **staging** | 2 | 100m CPU / 128Mi mem | ⚠️ After merge | Manual `workflow_dispatch` |
| **prod** | 3 | 250m CPU / 256Mi mem | ❌ Disabled | Manual + multi-gate approval |

Each environment gets:
- **Dedicated namespace** with complete resource isolation
- **Separate S3 state bucket** for Terraform (no cross-env contamination)
- **Consistent tagging strategy** (environment, project, managedBy, costCenter)
- **Independent lifecycle** (apply/destroy per environment)

---

## 📁 Project Structure

```
multi-gitops-pipeline/
├── README.md                      # This file
├── Makefile                       # Deploy targets: make dev/staging/prod/destroy-*
├── LICENSE                        # MIT — Thomas Wire
│
├── .github/workflows/
│   ├── ci.yml                     # CI: build, test, push to ECR, tfsec, trufflehog
│   ├── cd-dev.yml                 # CD: auto-promote new image to dev overlay
│   ├── cd-staging.yml             # CD: manual promotion gate for staging
│   ├── cd-prod.yml                # CD: multi-gate approval for production
│   └── drift-detection.yml        # Drift detection (cron: every 6h + manual)
│
├── providers/                     # Terraform: ECR, IAM, lifecycle policy
│   ├── main.tf                    # ECR repo, lifecycle policy, IRSA role
│   ├── variables.tf               # Input variables (consumes enterprise-terraform-aws outputs)
│   └── versions.tf                # Version constraints + S3 backend config
│
├── environments/                  # Environment-specific Terraform entry points
│   ├── dev/                       # Dev environment (cost-optimized)
│   │   ├── main.tf                # Provider + module call with S3 backend
│   │   └── variables.tf           # Variables from enterprise-terraform-aws
│   ├── staging/                   # Staging environment (production-like)
│   │   ├── main.tf
│   │   └── variables.tf
│   └── prod/                      # Production environment (full capacity)
│       ├── main.tf
│       └── variables.tf
│
├── k8s-manifests/                 # Kubernetes + Kustomize configuration
│   ├── base/                      # Kustomize base manifests
│   │   ├── deployment.yaml        # Order Service Deployment (1 replica default)
│   │   ├── configmap.yaml         # Environment variables (env, imageTag)
│   │   ├── service.yaml           # ClusterIP service on port 80
│   │   ├── network-policy.yaml    # Restrict ingress to namespace, egress to Redis + HTTPS
│   │   ├── redis-statefulset.yaml # Redis StatefulSet with PVC (1Gi gp3)
│   │   ├── redis-service.yaml     # Redis ClusterIP service on port 6379
│   │   └── kustomization.yaml     # Base overlay definition
│   │
│   ├── overlays/                  # Per-environment patches
│   │   ├── dev/                   # Dev: 1 replica, minimal resources
│   │   │   └── kustomization.yaml  # ConfigMap patch + resource limits + image ref
│   │   ├── staging/               # Staging: 2 replicas, production-like sizing
│   │   │   └── kustomization.yaml
│   │   └── prod/                  # Prod: 3 replicas, full resources
│   │       └── kustomization.yaml
│   │
│   └── argocd/                    # ArgoCD Application definitions
│       └── applications.yaml      # 3 Application CRDs (dev/staging/prod) with sync policies
│
├── src/                           # Application source code
│   ├── app.py                     # Flask microservice (health/readiness/config endpoints)
│   ├── Dockerfile                 # Multi-stage build (builder → production)
│   └── requirements.txt           # Python dependencies (flask, redis)
│
└── scripts/
    ├── setup.sh                   # One-command infrastructure setup
    └── destroy.sh                 # Clean teardown script
```

---

## 📦 Prerequisites

- [AWS CLI](https://aws.amazon.com/cli/) configured with credentials
- [Terraform](https://www.terraform.io/downloads.html) >= 1.10
- [kubectl](https://kubernetes.io/docs/tasks/tools/) for cluster interaction
- [GitHub Personal Access Token](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens) with `repo` and `packages:write` scopes (for CI)
- An AWS account with appropriate permissions

### Required IAM Permissions

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ecr:*", "ec2:*", "eks:*", "s3:*", "iam:*",
        "sts:AssumeRole"
      ],
      "Resource": "*"
    }
  ]
}
```

> ⚠️ For production, follow least-privilege principles and scope permissions to specific resources.

---

## 🚀 Quick Start

### 1. Ensure the EKS cluster exists

The `enterprise-terraform-aws` repo provisions the underlying cluster. Follow its setup instructions first:

```bash
cd ../enterprise-terraform-aws
./scripts/setup.sh dev
```

Then clone this repo and pass the EKS outputs:

```bash
git clone https://github.com/twire/multi-gitops-pipeline.git
cd multi-gitops-pipeline
```

### 2. Deploy infrastructure (ECR + IAM)

```bash
# Deploy for dev environment
make deploy ENV=dev

# This runs: Terraform → ECR repo + IAM role creation
```

The Makefile handles the full lifecycle:
1. **Terraform** — Creates ECR repository, lifecycle policy, IRSA role
2. **ArgoCD** — Applies Application CRDs that self-sync from Git overlays

### 3. Run CI to build & push image

Push any change to `main` to trigger the CI pipeline:

```bash
git add . && git commit -m "Initial commit" && git push origin main
```

The pipeline will:
1. **Build** the Flask app Docker image (multi-stage, non-root user)
2. **Scan** with Trivy for CVEs in the container image
3. **Push** to ECR as `latest` and `vYYYYMMDD-SHA`
4. **Update** the dev overlay via bot commit → ArgoCD auto-syncs

### 4. Access the application

After ArgoCD syncs (should be <30 seconds for dev):

```bash
# Watch pods come up
kubectl get pods -n order-service-api-dev -w

# Port-forward to access endpoints
kubectl port-forward svc/order-service-api 8080:80 -n order-service-api-dev

# Check health
curl http://localhost:8080/healthz    # {"status": "alive"}
curl http://localhost:8080/ready      # {"status": "ready", "redis": "connected"}
curl http://localhost:8080/config     # Shows environment-specific config (proves overlay)
curl http://localhost:8080/orders     # Redis-cached orders endpoint
```

### 5. Promote to staging & production

**To staging:** Trigger the manual promotion workflow:
```bash
gh workflow run cd-staging.yml \
  -f image_tag=v20260115-abc12345 \
  -f confirm_staging=APPROVE-STAGING
```

**To production:** Final multi-gate approval:
```bash
gh workflow run cd-prod.yml \
  -f image_tag=v20260115-abc12345 \
  -f confirm_production=APPROVE-PRODUCTION
```

---

## 🔄 CI Pipeline

Automated quality gates on every push/PR (GitHub Actions):

| Stage | Tool | What it checks |
|-------|------|----------------|
| **Build** | Docker Buildx + Trivy | Multi-stage build, CVE scanning (CRITICAL/HIGH only) |
| **Push** | AWS ECR | Image pushed as `latest` + `vYYYYMMDD-SHA` |
| **Validate** | Terraform `validate` | Syntax + provider compatibility across all envs |
| **Kustomize** | `kustomize build` | All overlays produce valid manifests |
| **Security** | tfsec | Insecure infrastructure configurations |
| **Secrets** | TruffleHog `--only-verified` | No AWS keys, passwords, tokens committed |

---

## 📡 CD Workflows

### Dev Promotion (Automatic)

Triggered automatically when CI completes successfully:

```yaml
# .github/workflows/cd-dev.yml
workflow_run:
  workflows: ["CI/CD - Multi-Stage Delivery Pipeline"]
  types: [completed]
  branches: [main, master]
```

The bot workflow:
1. Gets the latest image digest from ECR
2. Generates a version tag (`vYYYYMMDD-SHA`)
3. **Updates `k8s-manifests/overlays/dev/kustomization.yaml`** with the new image reference
4. Commits via the bot account → ArgoCD detects the change and auto-syncs

### Staging Promotion (Manual Gate)

Requires explicit workflow dispatch with confirmation:

```bash
gh workflow run cd-staging.yml \
  -f image_tag=v20260115-abc12345 \
  -f confirm_staging=APPROVE-STAGING
```

Verification steps:
1. Confirm gate (`confirm_staging=APPROVE-STAGING`)
2. Image must exist in ECR
3. Bot commits the overlay update to `main`

### Production Promotion (Multi-Gate)

Requires manual approval and validation:

```bash
gh workflow run cd-prod.yml \
  -f image_tag=v20260115-abc12345 \
  -f confirm_production=APPROVE-PRODUCTION
```

Gates enforced:
1. Manual confirmation (`confirm_production=APPROVE-PRODUCTION`)
2. Image verified in ECR (exists + not tampered)
3. In production, integrate with your ticketing/approval system

---

## 🔍 Drift Detection

### How It Works

A scheduled GitHub Action runs every 6 hours (or manually triggered) that:

1. **Builds desired state** from the Kustomize overlay for each environment
2. **Retrieves live state** from the Kubernetes cluster via `kubectl get`
3. **Compares** resource counts and field-level differences
4. **Creates a GitHub Issue** if drift is found (dev environment)

### What It Detects

| Drift Type | Detection Method | Example |
|-----------|-----------------|---------|
| **Replica count** | `kubectl diff` comparison | Someone manually scaled up via `kubectl scale` |
| **Resource limits** | Field-level manifest diff | Memory limits changed outside Git workflow |
| **Missing resources** | Resource count mismatch | Service deleted from cluster but not removed from Git |
| **Image version** | Image tag in Deployment spec | Manual image change bypassing CI/CD pipeline |

### Why It Matters

In a pure GitOps model, the cluster state should **always match** what's defined in Git. Drift detection alerts you when:
- Emergency manual changes were made without updating Git
- ArgoCD failed to sync and was ignored
- Someone edited manifests directly via `kubectl apply` (anti-pattern!)

---

## 🔑 Key Patterns

### 1. Kustomize Overlay Promotion

Each environment's desired state lives in a separate overlay directory. The overlays share a common base but patch resource limits, replica counts, and ConfigMap values:

```
base/                              # Shared manifests (deployment, service, network policy)
├── overlays/dev/kustomization.yaml   # 1 replica, minimal resources, auto-sync
├── overlays/staging/kustomization.yaml # 2 replicas, production-like sizing, gated
└── overlays/prod/kustomization.yaml    # 3 replicas, full capacity, manual gate only
```

The `images` section in each overlay's kustomization.yaml is the single point of truth for which image version to deploy — CI updates this field and ArgoCD picks it up.

### 2. Bot Account Manifest Updates

Instead of having developers manually update image tags, a GitHub Actions bot account commits overlay changes after each successful build:

- `stefanzweifel/git-auto-commit-action` handles the commit with proper bot identity
- Changes are visible in git history with consistent author attribution
- ArgoCD detects the change within seconds and triggers sync

### 3. Progressive Trust Model

| Stage | Automation Level | Trust Required | Sync Mode |
|-------|-----------------|----------------|-----------|
| Dev | 100% automated | Low (CI pipeline) | `selfHeal: true` |
| Staging | 80% automated | Medium (manual trigger) | `selfHeal: true` |
| Prod | 20% automated | High (multi-gate) | `selfHeal: false` |

This mirrors real-world enterprise release management where production changes require human judgment.

### 4. Scheduled Drift Detection

Instead of relying solely on ArgoCD's reconciliation loop, an external cron job provides an independent verification layer:

```yaml
on:
  schedule:
    - cron: '0 */6 * * *'  # Every 6 hours
  workflow_dispatch:          # Manual trigger for audits
```

This catches drift that might be missed if ArgoCD itself is compromised or misconfigured.

### 5. ECR Lifecycle Management

Old images are automatically cleaned up to prevent storage bloat:

```json
{
  "rules": [{
    "rulePriority": 1,
    "selection": {
      "tagStatus": "tagged",
      "tagPrefixList": ["v", "latest"],
      "countType": "imageCountMoreThan",
      "countNumber": 30
    },
    "action": { "type": "expire" }
  }]
}
```

### 6. IRSA for ArgoCD ECR Access

ArgoCD's application controller assumes an IAM role to pull images from ECR — no static credentials needed:

```yaml
# In enterprise-terraform-aws, the OIDC provider is created
# This repo references it via eks_oidc_arn and eks_oidc_url variables
```

---

## 💰 Cost Estimates (per environment)

| Resource | dev | staging | prod |
|----------|-----|---------|------|
| EKS Cluster control plane | $0.10/hr | $0.10/hr | $0.10/hr |
| Order Service Pods | ~$0.004/hr | ~$0.025/hr | ~$0.085/hr |
| Redis StatefulSet | ~$0.007/hr | ~$0.007/hr | ~$0.007/hr |
| ECR Storage (~30 images) | ~$0.15/mo | (shared repo) | (shared repo) |
| NAT Gateway (if separate VPC) | $0.045/hr | $0.045/hr | $0.045/hr |
| **~Total/hr** | **~$0.16** | **~$0.17** | **~$0.23** |

> 💡 **Tip:** Share one ECR repository across all environments (as designed) to keep storage costs minimal. Total monthly cost: **~$115-$165** depending on environment count.

---

## 🔒 Security Highlights

| Feature | Implementation |
|---------|---------------|
| **ECR scanning** | Image scan on push via ECR native scanning + Trivy in CI |
| **IRSA for ArgoCD** | No AWS credentials in ArgoCD config or env vars |
| **Non-root containers** | Dockerfile uses `appuser` (non-root) with securityContext |
| **NetworkPolicies** | Restrict ingress to namespace, egress to Redis + HTTPS only |
| **ECR lifecycle** | Auto-expire old images — prevents unbounded storage growth |
| **TruffleHog in CI** | No secrets committed to git history (even partial/rotated) |
| **tfsec in CI** | Infrastructure-as-code security scanning on every commit |

---

## 🧹 Destroy

```bash
# Clean up pipeline infrastructure only (does NOT destroy the EKS cluster)
make destroy-terraform ENV=dev    # or staging / prod
```

This removes: ECR repository, lifecycle policy, IAM roles. The EKS cluster and ArgoCD Applications from `enterprise-terraform-aws` remain intact.

To tear down everything including the cluster:
```bash
cd ../enterprise-terraform-aws
./scripts/destroy.sh dev
```

---

## 🎯 Interview Talking Points

This project demonstrates:

1. **Multi-stage GitOps** — Full promotion pipeline with automated dev sync, manual staging gates, and production approval workflows
2. **Kustomize overlays** — Environment-specific configuration without forking manifests or using Helm
3. **Bot-driven manifest updates** | CI automatically commits image tag changes that ArgoCD picks up via self-heal
4. **Progressive trust model** | Different sync policies per environment (auto → gated → manual) matching enterprise release practices
5. **Drift detection** | Scheduled external verification catching cluster-to-Git divergence that ArgoCD alone might miss
6. **ECR lifecycle management** | Automated image retention to prevent storage bloat
7. **Production readiness patterns** | Health probes, network policies, IRSA, non-root containers

**Common interview questions this can answer:**
- "How do you manage promotion from dev to production?" → Three-stage pipeline with Kustomize overlays, bot commits, and ArgoCD self-heal — different trust levels per stage
- "What happens when someone makes manual changes to the cluster?" | Drift detection catches it in 6 hours via scheduled GitHub Actions comparing Git manifests against live state
- "How do you update images without developers touching manifests?" → CI updates Kustomize overlay's `images` section, bot commits, ArgoCD auto-syncs within seconds
- "Why not just use Helm for environments?" | Kustomize is lighter weight for overlay-based differentiation; Helm charts are already used by enterprise-terraform-aws and eks-observability — keeping the stack diverse shows breadth
- "How do you prevent production changes from being lost?" | `selfHeal: false` in prod means ArgoCD won't revert manual emergency fixes; drift detection catches them for later remediation

---

## 📜 License

MIT — Feel free to use, modify, and showcase this in your portfolio!

---

> **Built by [Thomas Wire](https://github.com/tomwire)** — Showcasing enterprise-grade CI/CD with ArgoCD GitOps, Kustomize, and drift detection on AWS EKS.
