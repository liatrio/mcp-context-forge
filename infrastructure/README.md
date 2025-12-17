# MCP Gateway AWS Infrastructure

This directory contains Terraform configurations for deploying MCP Context Forge (MCP Gateway) to AWS using ECS Fargate and managed services.

## Architecture

The deployment uses:
- **Amazon ECS Fargate** - Serverless containers
- **Amazon RDS PostgreSQL** - Managed database with automatic backups and password rotation
- **Amazon ElastiCache Redis** - Managed caching layer
- **AWS Secrets Manager** - Secure credential storage with automatic rotation
- **Application Load Balancer** - TLS termination and routing
- **Amazon CloudWatch** - Centralized logging, metrics, and dashboards
- **AWS Certificate Manager** - Free TLS certificates

For the complete architecture overview, cost estimates, and deployment details, see [DEPLOYMENT_PLAN.md](DEPLOYMENT_PLAN.md).

## Prerequisites

- Terraform >= 1.10.0
- AWS CLI configured with `liatrio` profile
- Access to AWS account 008971644846

## Quick Start

```bash
cd infrastructure

# Initialize Terraform (downloads providers and modules)
terraform init

# Review planned changes
AWS_PROFILE=liatrio terraform plan

# Apply changes
AWS_PROFILE=liatrio terraform apply
```

## Configuration

Copy `terraform.tfvars.example` to `terraform.tfvars` and customize for your environment. Key settings:

| Variable | Description | Default |
|----------|-------------|---------|
| `aws_region` | AWS region | `us-east-2` |
| `environment` | Environment name | `dev` |
| `domain_name` | Application domain | `mcp-gateway.dev.pop-platform.liatr.io` |
| `container_image` | Docker image to deploy | `ghcr.io/ibm/mcp-context-forge:1.0.0-BETA-1` |

### SSO Configuration

GitHub OAuth SSO is supported. Configure in `terraform.tfvars`:

```hcl
sso_enabled              = true
sso_github_enabled       = true
sso_github_client_id     = "your-client-id"
sso_github_client_secret = "your-client-secret"
sso_github_admin_orgs    = ["YourOrg"]
```

## File Structure

```
infrastructure/
├── main.tf              # VPC, ALB, RDS, ElastiCache, KMS
├── ecs.tf               # ECS cluster, task definition, service, auto-scaling
├── secrets.tf           # Secrets Manager secrets
├── monitoring.tf        # CloudWatch dashboard, alarms, log groups
├── secret-rotation.tf   # Lambda for RDS password rotation handling
├── state.tf             # S3 backend for Terraform state
├── variables.tf         # Input variables
├── outputs.tf           # Output values
├── versions.tf          # Provider versions and backend config
├── terraform.tfvars     # Variable values (gitignored)
├── DEPLOYMENT_PLAN.md   # Detailed deployment documentation
└── README.md            # This file
```

## Terraform State

State is stored in S3 with native locking (Terraform 1.10+):
- **Bucket:** `mcp-gateway-dev-terraform-state`
- **Region:** `us-east-2`
- **Encryption:** KMS

## Common Operations

### Force new deployment (rolling update)
```bash
AWS_PROFILE=liatrio aws ecs update-service \
  --cluster mcp-gateway-dev-cluster \
  --service mcp-gateway-dev \
  --force-new-deployment \
  --region us-east-2
```

### View logs
```bash
AWS_PROFILE=liatrio aws logs tail /aws/ecs/mcp-gateway-dev --follow --region us-east-2
```

### Scale manually
```bash
AWS_PROFILE=liatrio aws ecs update-service \
  --cluster mcp-gateway-dev-cluster \
  --service mcp-gateway-dev \
  --desired-count 4 \
  --region us-east-2
```

## Security Notes

- All secrets are stored in AWS Secrets Manager with KMS encryption
- RDS passwords are auto-rotated every 30 days via AWS-managed rotation
- A Lambda function automatically updates the DATABASE_URL secret and triggers ECS redeployment when RDS credentials rotate
- VPC Flow Logs are enabled for network monitoring
- TLS 1.3 is enforced on the ALB

## Cost Estimate

See [DEPLOYMENT_PLAN.md](DEPLOYMENT_PLAN.md#10-cost-estimation) for detailed cost breakdown. Approximate monthly cost for single-AZ deployment: ~$142/month.
