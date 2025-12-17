# AWS Deployment Plan for MCP Context Forge

This document outlines a low-maintenance, enterprise-grade deployment of MCP Context Forge (MCP Gateway) on AWS using ECS Fargate and managed services.

## Target Environment

| Setting | Value |
|---------|-------|
| **AWS Account** | 008971644846 |
| **Region** | us-east-2 (Ohio) |
| **AWS Profile** | `liatrio` |
| **Domain** | `mcp-gateway.dev.pop-platform.liatr.io` |
| **Route53 Zone** | `dev.pop-platform.liatr.io` (Z04526022XWDTY6SX40DX) |

## Executive Summary

**Recommended Approach**: AWS ECS Fargate + Managed Services

This deployment leverages:
- **Amazon ECS with Fargate** - Serverless containers (no clusters or nodes to manage)
- **Amazon RDS for PostgreSQL** - Managed database with automatic backups
- **Amazon ElastiCache for Redis** - Managed caching layer
- **AWS Secrets Manager** - Secure credential storage
- **Application Load Balancer** - TLS termination and routing
- **Amazon CloudWatch** - Centralized logging and monitoring
- **AWS Certificate Manager** - Free TLS certificates

**Why ECS Fargate over EKS?**
- Simpler operational model (no Kubernetes knowledge required)
- No cluster management or control plane costs
- Native AWS integrations work out of the box
- Lower cost for smaller workloads
- Faster deployment and easier debugging

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              AWS Cloud                                       │
│  ┌────────────────────────────────────────────────────────────────────────┐ │
│  │                         VPC (10.0.0.0/16)                              │ │
│  │                                                                        │ │
│  │  ┌──────────────────────┐                                              │ │
│  │  │   Internet Gateway    │                                              │ │
│  │  └──────────┬───────────┘                                              │ │
│  │             │                                                          │ │
│  │  ┌──────────▼───────────┐                                              │ │
│  │  │ Application Load     │◄──── AWS Certificate Manager (TLS)           │ │
│  │  │ Balancer (Public)    │                                              │ │
│  │  └──────────┬───────────┘                                              │ │
│  │             │                                                          │ │
│  │  ┌──────────┴───────────────────────────────────────────┐              │ │
│  │  │              Public Subnet (1 AZ)                     │              │ │
│  │  │                    ┌─────────────┐                   │              │ │
│  │  │                    │ NAT Gateway │                   │              │ │
│  │  │                    └──────┬──────┘                   │              │ │
│  │  └───────────────────────────┼──────────────────────────┘              │ │
│  │                              │                                         │ │
│  │  ┌───────────────────────────┴──────────────────────────┐              │ │
│  │  │              Private Subnet (1 AZ)                    │              │ │
│  │  │                                                       │              │ │
│  │  │  ┌─────────────────────────────────────────────────┐ │              │ │
│  │  │  │              ECS Fargate Cluster                 │ │              │ │
│  │  │  │                                                  │ │              │ │
│  │  │  │   ┌─────────────┐  ┌─────────────┐              │ │              │ │
│  │  │  │   │   Task 1    │  │   Task 2    │  ... (auto)  │ │              │ │
│  │  │  │   │ MCP Gateway │  │ MCP Gateway │              │ │              │ │
│  │  │  │   │ (2 workers) │  │ (2 workers) │              │ │              │ │
│  │  │  │   └─────────────┘  └─────────────┘              │ │              │ │
│  │  │  │                                                  │ │              │ │
│  │  │  └─────────────────────────────────────────────────┘ │              │ │
│  │  │                          │                           │              │ │
│  │  │     ┌────────────────────┴─────────────────────┐    │              │ │
│  │  │     │                    │                     │    │              │ │
│  │  │     ▼                    ▼                     ▼    │              │ │
│  │  │  ┌──────────────┐  ┌──────────────┐  ┌─────────────┐│              │ │
│  │  │  │ RDS          │  │ ElastiCache  │  │ Secrets     ││              │ │
│  │  │  │ PostgreSQL   │  │ Redis        │  │ Manager     ││              │ │
│  │  │  │ (Single-AZ)  │  │ (Single)     │  │             ││              │ │
│  │  │  └──────────────┘  └──────────────┘  └─────────────┘│              │ │
│  │  └──────────────────────────────────────────────────────┘              │ │
│  │                                                                        │ │
│  └────────────────────────────────────────────────────────────────────────┘ │
│                                                                              │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐              │
│  │   CloudWatch    │  │   AWS Backup    │  │    Route 53     │              │
│  │ (Logs/Metrics)  │  │ (Snapshots)     │  │ (DNS)           │              │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘              │
└─────────────────────────────────────────────────────────────────────────────┘
```

> **Note:** This single-AZ configuration is optimized for initial deployment and cost savings.
> For production HA, expand to 2 AZs by adding a second subnet and enabling Multi-AZ on RDS/ElastiCache.

---

## Current AWS State

### us-east-2 (Target Region - Clean Slate)

| Resource | Status | Notes |
|----------|--------|-------|
| VPC | None | Must create new |
| Subnets | None | Must create new |
| NAT Gateway | None | Must create new |
| Internet Gateway | None | Must create new |
| ECS Clusters | None | Must create new |
| RDS Instances | None | Must create new |
| ElastiCache | None | Must create new |
| ACM Certificates | None | Must create new |
| Secrets Manager | None | Must create new |

**Available AZs:** `us-east-2a`, `us-east-2b`, `us-east-2c`

**Deployment Target:** `us-east-2a` (single AZ for initial deployment)

### us-east-1 (Reference - Existing Infrastructure)

| Resource | Status | Notes |
|----------|--------|-------|
| VPCs | 3 existing | `tailscale-proxy-dev-tailscale-vpc`, `private-vpn-vpc`, `tailscale-proxy-dev-web-app-vpc` |
| NAT Gateways | 2 existing | `private-vpn-nat`, `web-app-dev-nat-gateway` |
| ECS Clusters | None | - |
| RDS Instances | None | - |
| ElastiCache | None | - |
| ACM Certificates | 3 | `dev.pop-platform.liatr.io` (EXPIRED), `vpn.pop-platform.liatr.io`, `vpn-ca.local` |

> **Note:** us-east-1 has VPN/Tailscale infrastructure. MCP Gateway will deploy to us-east-2 to keep environments separate.

### Global Resources

| Resource | Status | Notes |
|----------|--------|-------|
| Route53 Zone | **Exists** | `dev.pop-platform.liatr.io` (Z04526022XWDTY6SX40DX) |
| ECS Service Role | **Exists** | `AWSServiceRoleForECS` (auto-created) |

---

## Terraform Resource Summary

All infrastructure will be created via Terraform in the `infrastructure/` folder at the repository root, using **community AWS modules** where possible to reduce custom code.

**Directory Structure:**

```text
infrastructure/
├── main.tf              # Root module, provider config
├── variables.tf         # Input variables
├── outputs.tf           # Output values
├── versions.tf          # Terraform and provider versions
├── terraform.tfvars     # Variable values (gitignored secrets)
└── .terraform.lock.hcl  # Provider lock file
```

**Community Modules to Use:**

| Module | Source | Purpose |
|--------|--------|---------|
| VPC | `terraform-aws-modules/vpc/aws` | VPC, subnets, NAT, IGW, route tables |
| Security Groups | `terraform-aws-modules/security-group/aws` | ALB, ECS, RDS, Redis security groups |
| ALB | `terraform-aws-modules/alb/aws` | Load balancer, listeners, target groups |
| RDS | `terraform-aws-modules/rds/aws` | PostgreSQL instance, subnet group, parameter group |
| ElastiCache | `terraform-aws-modules/elasticache/aws` | Redis cluster, subnet group |
| ECS | `terraform-aws-modules/ecs/aws` | ECS cluster, capacity providers |
| ACM | `terraform-aws-modules/acm/aws` | Certificate, DNS validation |

**Custom Resources (not covered by modules):**

```hcl
# ECS Service & Task Definition (module doesn't cover Fargate services well)
aws_ecs_task_definition.app
aws_ecs_service.app

# IAM Roles for ECS
aws_iam_role.ecs_execution
aws_iam_role.ecs_task
aws_iam_role_policy_attachment.ecs_execution
aws_iam_policy.ecs_secrets_access

# Secrets Manager
aws_secretsmanager_secret.app_secrets
aws_secretsmanager_secret_version.app_secrets

# Route53 Record (for app DNS)
aws_route53_record.app

# Auto Scaling
aws_appautoscaling_target.ecs
aws_appautoscaling_policy.cpu
aws_appautoscaling_policy.memory

# CloudWatch Log Group
aws_cloudwatch_log_group.ecs
```

**Example Module Usage:**

```hcl
# VPC with single AZ (minimal config)
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "mcp-gateway-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["us-east-2a"]
  private_subnets = ["10.0.10.0/24"]
  public_subnets  = ["10.0.1.0/24"]

  enable_nat_gateway = true
  single_nat_gateway = true

  tags = {
    Environment = "dev"
    Project     = "mcp-gateway"
  }
}

# ALB
module "alb" {
  source  = "terraform-aws-modules/alb/aws"
  version = "~> 9.0"

  name               = "mcp-gateway-alb"
  load_balancer_type = "application"
  vpc_id             = module.vpc.vpc_id
  subnets            = module.vpc.public_subnets
  security_groups    = [module.alb_sg.security_group_id]

  # ... listeners and target groups
}

# RDS PostgreSQL
module "rds" {
  source  = "terraform-aws-modules/rds/aws"
  version = "~> 6.0"

  identifier           = "mcp-gateway-db"
  engine               = "postgres"
  engine_version       = "16.4"
  family               = "postgres16"
  instance_class       = "db.t4g.micro"
  allocated_storage    = 20
  max_allocated_storage = 100

  db_name  = "mcpgateway"
  username = "mcpgateway"
  port     = 5432

  vpc_security_group_ids = [module.rds_sg.security_group_id]
  db_subnet_group_name   = module.vpc.database_subnet_group_name

  # Single AZ for initial deployment
  multi_az = false

  # Backups
  backup_retention_period = 7
  deletion_protection     = true

  # Encryption
  storage_encrypted = true
}

# ACM Certificate with DNS validation
module "acm" {
  source  = "terraform-aws-modules/acm/aws"
  version = "~> 5.0"

  domain_name = "mcp-gateway.dev.pop-platform.liatr.io"
  zone_id     = "Z04526022XWDTY6SX40DX"

  validation_method = "DNS"
  wait_for_validation = true
}
```

---

## 1. Infrastructure Setup

### 1.1 VPC and Networking

Create a VPC with public and private subnets in a single Availability Zone:

```bash
# Create VPC
aws ec2 create-vpc \
  --cidr-block 10.0.0.0/16 \
  --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=mcp-gateway-vpc}]'
```

**Subnet Layout (Single AZ):**

| Subnet Type | CIDR Block | Purpose |
|------------|------------|---------|
| Public AZ-a | 10.0.1.0/24 | NAT Gateway, ALB |
| Private AZ-a | 10.0.10.0/24 | ECS Tasks, RDS, ElastiCache |

> **Expanding to Multi-AZ later:** Add `10.0.2.0/24` (public) and `10.0.20.0/24` (private) in AZ-b.

### 1.2 Security Groups

Create security groups with least-privilege access:

| Security Group | Inbound Rules | Purpose |
|---------------|---------------|---------|
| `sg-alb` | 443/TCP from 0.0.0.0/0 | Application Load Balancer |
| `sg-ecs` | 4444/TCP from sg-alb | MCP Gateway containers |
| `sg-rds` | 5432/TCP from sg-ecs | PostgreSQL database |
| `sg-redis` | 6379/TCP from sg-ecs | ElastiCache Redis |

```bash
# Create ALB security group
aws ec2 create-security-group \
  --group-name sg-mcp-alb \
  --description "ALB for MCP Gateway" \
  --vpc-id vpc-xxx

aws ec2 authorize-security-group-ingress \
  --group-id sg-alb-xxx \
  --protocol tcp \
  --port 443 \
  --cidr 0.0.0.0/0

# Create ECS security group
aws ec2 create-security-group \
  --group-name sg-mcp-ecs \
  --description "ECS tasks for MCP Gateway" \
  --vpc-id vpc-xxx

aws ec2 authorize-security-group-ingress \
  --group-id sg-ecs-xxx \
  --protocol tcp \
  --port 4444 \
  --source-group sg-alb-xxx
```

---

## 2. Data Storage

### 2.1 Amazon RDS for PostgreSQL

**Configuration:**

```yaml
Engine: PostgreSQL 16
Instance Class: db.t4g.micro (2 vCPU, 1 GB RAM) - minimal for initial deployment
Storage: 20 GB gp3 (with auto-scaling up to 100 GB)
Multi-AZ: Disabled (single AZ for initial deployment)
Encryption: Enabled (AWS KMS)
Backup Retention: 7 days
Performance Insights: Enabled (free tier)
```

**Create RDS Instance:**
```bash
# Create DB subnet group (single subnet for initial deployment)
aws rds create-db-subnet-group \
  --db-subnet-group-name mcp-gateway-db-subnet \
  --db-subnet-group-description "Subnet for MCP Gateway RDS" \
  --subnet-ids subnet-private-a

# Create RDS instance (single AZ, minimal size)
aws rds create-db-instance \
  --db-instance-identifier mcp-gateway-db \
  --db-instance-class db.t4g.micro \
  --engine postgres \
  --engine-version 16.4 \
  --master-username mcpgateway \
  --manage-master-user-password \
  --allocated-storage 20 \
  --max-allocated-storage 100 \
  --storage-type gp3 \
  --storage-encrypted \
  --kms-key-id alias/aws/rds \
  --no-multi-az \
  --vpc-security-group-ids sg-rds-xxx \
  --db-subnet-group-name mcp-gateway-db-subnet \
  --db-name mcpgateway \
  --backup-retention-period 7 \
  --enable-performance-insights \
  --performance-insights-retention-period 7 \
  --deletion-protection \
  --tags Key=Environment,Value=production
```

**PostgreSQL Parameters (via Parameter Group):**

```
max_connections = 50
shared_buffers = 256MB
effective_cache_size = 512MB
work_mem = 4MB
```

### 2.2 Amazon ElastiCache for Redis

**Configuration:**

```yaml
Engine: Redis 7.x
Node Type: cache.t4g.micro (0.5 GB RAM) - minimal for initial deployment
Number of Nodes: 1 (single node, no replica)
Multi-AZ: Disabled
Encryption at Rest: Enabled (AWS KMS)
Encryption in Transit: Enabled (TLS)
Auth Token: Enabled
Automatic Backups: Daily, 3-day retention
```

**Create ElastiCache Cluster:**

```bash
# Create cache subnet group (single subnet)
aws elasticache create-cache-subnet-group \
  --cache-subnet-group-name mcp-gateway-cache-subnet \
  --cache-subnet-group-description "Subnet for MCP Gateway Redis" \
  --subnet-ids subnet-private-a

# Create single Redis node (no replication for initial deployment)
aws elasticache create-cache-cluster \
  --cache-cluster-id mcp-gateway-redis \
  --engine redis \
  --engine-version 7.1 \
  --cache-node-type cache.t4g.micro \
  --num-cache-nodes 1 \
  --cache-subnet-group-name mcp-gateway-cache-subnet \
  --security-group-ids sg-redis-xxx \
  --snapshot-retention-limit 3 \
  --tags Key=Environment,Value=production
```

> **Note:** For HA, upgrade to a replication group with `--num-cache-clusters 2` and `--automatic-failover-enabled`.

---

## 3. Encryption at Rest and In Transit

### 3.1 Encryption at Rest

| Service | Encryption Method | Key Management |
|---------|------------------|----------------|
| RDS PostgreSQL | AES-256 | AWS KMS (CMK) |
| ElastiCache Redis | AES-256 | AWS KMS (CMK) |
| ECS Task Storage | AES-256 | AWS KMS (default) |
| CloudWatch Logs | AES-256 | AWS KMS (CMK) |
| Secrets Manager | AES-256 | AWS KMS (CMK) |

**Create Customer Managed Key:**
```bash
aws kms create-key \
  --description "MCP Gateway encryption key" \
  --key-usage ENCRYPT_DECRYPT \
  --tags TagKey=Application,TagValue=mcp-gateway

# Create alias for easier reference
aws kms create-alias \
  --alias-name alias/mcp-gateway \
  --target-key-id <key-id>
```

### 3.2 Encryption in Transit

| Connection | Protocol | Certificate |
|-----------|----------|-------------|
| Client → ALB | TLS 1.3 | ACM Certificate |
| ALB → ECS Tasks | HTTP (internal VPC) | N/A |
| ECS → RDS | TLS 1.2+ | RDS CA Certificate |
| ECS → Redis | TLS 1.2+ | ElastiCache CA |

**Request ACM Certificate:**

```bash
aws acm request-certificate \
  --region us-east-2 \
  --domain-name mcp-gateway.dev.pop-platform.liatr.io \
  --validation-method DNS
```

> **Note:** DNS validation will create a CNAME record in the existing Route53 zone `dev.pop-platform.liatr.io`.

---

## 4. Secrets Management

### 4.1 AWS Secrets Manager

Store all sensitive configuration in Secrets Manager:

```bash
# Create secret for application secrets
aws secretsmanager create-secret \
  --name mcp-gateway/app-secrets \
  --secret-string '{
    "JWT_SECRET_KEY": "'$(openssl rand -hex 32)'",
    "AUTH_ENCRYPTION_SECRET": "'$(openssl rand -hex 32)'",
    "BASIC_AUTH_PASSWORD": "'$(openssl rand -base64 24)'",
    "PLATFORM_ADMIN_PASSWORD": "'$(openssl rand -base64 24)'"
  }'

# Create secret for Redis auth token
aws secretsmanager create-secret \
  --name mcp-gateway/redis \
  --secret-string '{"auth_token":"'$(openssl rand -base64 32)'"}'

# Create secret for SSO (if using Microsoft Entra ID)
aws secretsmanager create-secret \
  --name mcp-gateway/sso \
  --secret-string '{
    "SSO_ENTRA_CLIENT_ID": "<azure-client-id>",
    "SSO_ENTRA_CLIENT_SECRET": "<azure-client-secret>",
    "SSO_ENTRA_TENANT_ID": "<azure-tenant-id>"
  }'
```

**Note:** RDS credentials are automatically managed when using `--manage-master-user-password`.

---

## 5. ECS Fargate Setup

### 5.1 Create ECS Cluster

```bash
aws ecs create-cluster \
  --cluster-name mcp-gateway-cluster \
  --capacity-providers FARGATE FARGATE_SPOT \
  --default-capacity-provider-strategy capacityProvider=FARGATE,weight=1 \
  --configuration executeCommandConfiguration={logging=OVERRIDE,logConfiguration={cloudWatchLogGroupName=/aws/ecs/mcp-gateway}} \
  --settings name=containerInsights,value=enabled \
  --tags key=Environment,value=production
```

### 5.2 Create IAM Roles

**Task Execution Role** (for ECS to pull images and secrets):
```bash
# Create execution role
aws iam create-role \
  --role-name mcp-gateway-execution-role \
  --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Principal": {"Service": "ecs-tasks.amazonaws.com"},
      "Action": "sts:AssumeRole"
    }]
  }'

# Attach managed policy
aws iam attach-role-policy \
  --role-name mcp-gateway-execution-role \
  --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy

# Add secrets access
aws iam put-role-policy \
  --role-name mcp-gateway-execution-role \
  --policy-name SecretsAccess \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Action": ["secretsmanager:GetSecretValue"],
      "Resource": "arn:aws:secretsmanager:*:*:secret:mcp-gateway/*"
    }]
  }'
```

**Task Role** (for the application itself):
```bash
aws iam create-role \
  --role-name mcp-gateway-task-role \
  --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Principal": {"Service": "ecs-tasks.amazonaws.com"},
      "Action": "sts:AssumeRole"
    }]
  }'

# Add CloudWatch Logs access
aws iam put-role-policy \
  --role-name mcp-gateway-task-role \
  --policy-name CloudWatchLogs \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Action": ["logs:CreateLogStream", "logs:PutLogEvents"],
      "Resource": "arn:aws:logs:*:*:log-group:/aws/ecs/mcp-gateway:*"
    }]
  }'
```

### 5.3 Create Task Definition

Create `task-definition.json`:

```json
{
  "family": "mcp-gateway",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "512",
  "memory": "1024",
  "executionRoleArn": "arn:aws:iam::ACCOUNT:role/mcp-gateway-execution-role",
  "taskRoleArn": "arn:aws:iam::ACCOUNT:role/mcp-gateway-task-role",
  "containerDefinitions": [
    {
      "name": "mcp-gateway",
      "image": "ghcr.io/ibm/mcp-context-forge:1.0.0-BETA-1",
      "essential": true,
      "portMappings": [
        {
          "containerPort": 4444,
          "protocol": "tcp"
        }
      ],
      "environment": [
        {"name": "HOST", "value": "0.0.0.0"},
        {"name": "PORT", "value": "4444"},
        {"name": "GUNICORN_WORKERS", "value": "2"},
        {"name": "GUNICORN_TIMEOUT", "value": "600"},
        {"name": "GUNICORN_MAX_REQUESTS", "value": "10000"},
        {"name": "GUNICORN_PRELOAD_APP", "value": "true"},
        {"name": "DB_POOL_SIZE", "value": "5"},
        {"name": "DB_MAX_OVERFLOW", "value": "2"},
        {"name": "DB_POOL_TIMEOUT", "value": "30"},
        {"name": "CACHE_TYPE", "value": "redis"},
        {"name": "CACHE_PREFIX", "value": "mcpgw:"},
        {"name": "SESSION_TTL", "value": "3600"},
        {"name": "MESSAGE_TTL", "value": "600"},
        {"name": "ENVIRONMENT", "value": "production"},
        {"name": "APP_DOMAIN", "value": "mcp-gateway.dev.pop-platform.liatr.io"},
        {"name": "MCPGATEWAY_UI_ENABLED", "value": "false"},
        {"name": "MCPGATEWAY_ADMIN_API_ENABLED", "value": "false"},
        {"name": "AUTH_REQUIRED", "value": "true"},
        {"name": "SECURE_COOKIES", "value": "true"},
        {"name": "COOKIE_SAMESITE", "value": "strict"},
        {"name": "LOG_LEVEL", "value": "INFO"},
        {"name": "LOG_FORMAT", "value": "json"},
        {"name": "OTEL_ENABLE_OBSERVABILITY", "value": "true"},
        {"name": "OTEL_SERVICE_NAME", "value": "mcp-gateway"}
      ],
      "secrets": [
        {
          "name": "DATABASE_URL",
          "valueFrom": "arn:aws:secretsmanager:REGION:ACCOUNT:secret:rds!db-xxx:url::"
        },
        {
          "name": "REDIS_URL",
          "valueFrom": "arn:aws:secretsmanager:REGION:ACCOUNT:secret:mcp-gateway/redis:url::"
        },
        {
          "name": "JWT_SECRET_KEY",
          "valueFrom": "arn:aws:secretsmanager:REGION:ACCOUNT:secret:mcp-gateway/app-secrets:JWT_SECRET_KEY::"
        },
        {
          "name": "AUTH_ENCRYPTION_SECRET",
          "valueFrom": "arn:aws:secretsmanager:REGION:ACCOUNT:secret:mcp-gateway/app-secrets:AUTH_ENCRYPTION_SECRET::"
        },
        {
          "name": "BASIC_AUTH_USER",
          "valueFrom": "arn:aws:secretsmanager:REGION:ACCOUNT:secret:mcp-gateway/app-secrets:BASIC_AUTH_USER::"
        },
        {
          "name": "BASIC_AUTH_PASSWORD",
          "valueFrom": "arn:aws:secretsmanager:REGION:ACCOUNT:secret:mcp-gateway/app-secrets:BASIC_AUTH_PASSWORD::"
        },
        {
          "name": "PLATFORM_ADMIN_EMAIL",
          "valueFrom": "arn:aws:secretsmanager:REGION:ACCOUNT:secret:mcp-gateway/app-secrets:PLATFORM_ADMIN_EMAIL::"
        },
        {
          "name": "PLATFORM_ADMIN_PASSWORD",
          "valueFrom": "arn:aws:secretsmanager:REGION:ACCOUNT:secret:mcp-gateway/app-secrets:PLATFORM_ADMIN_PASSWORD::"
        }
      ],
      "healthCheck": {
        "command": ["CMD-SHELL", "curl -f http://localhost:4444/health || exit 1"],
        "interval": 30,
        "timeout": 5,
        "retries": 3,
        "startPeriod": 60
      },
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/aws/ecs/mcp-gateway",
          "awslogs-region": "us-east-1",
          "awslogs-stream-prefix": "mcp-gateway"
        }
      }
    }
  ]
}
```

**Register Task Definition:**
```bash
aws ecs register-task-definition --cli-input-json file://task-definition.json
```

### 5.4 Create Application Load Balancer

```bash
# Create ALB
aws elbv2 create-load-balancer \
  --name mcp-gateway-alb \
  --subnets subnet-public-a \
  --security-groups sg-alb-xxx \
  --scheme internet-facing \
  --type application \
  --tags Key=Environment,Value=production

# Create target group
aws elbv2 create-target-group \
  --name mcp-gateway-tg \
  --protocol HTTP \
  --port 4444 \
  --vpc-id vpc-xxx \
  --target-type ip \
  --health-check-enabled \
  --health-check-path /health \
  --health-check-interval-seconds 30 \
  --healthy-threshold-count 2 \
  --unhealthy-threshold-count 3

# Create HTTPS listener
aws elbv2 create-listener \
  --load-balancer-arn arn:aws:elasticloadbalancing:REGION:ACCOUNT:loadbalancer/app/mcp-gateway-alb/xxx \
  --protocol HTTPS \
  --port 443 \
  --ssl-policy ELBSecurityPolicy-TLS13-1-2-2021-06 \
  --certificates CertificateArn=arn:aws:acm:REGION:ACCOUNT:certificate/xxx \
  --default-actions Type=forward,TargetGroupArn=arn:aws:elasticloadbalancing:REGION:ACCOUNT:targetgroup/mcp-gateway-tg/xxx

# Create HTTP to HTTPS redirect
aws elbv2 create-listener \
  --load-balancer-arn arn:aws:elasticloadbalancing:REGION:ACCOUNT:loadbalancer/app/mcp-gateway-alb/xxx \
  --protocol HTTP \
  --port 80 \
  --default-actions Type=redirect,RedirectConfig='{Protocol=HTTPS,Port=443,StatusCode=HTTP_301}'
```

### 5.5 Create ECS Service

```bash
aws ecs create-service \
  --cluster mcp-gateway-cluster \
  --service-name mcp-gateway \
  --task-definition mcp-gateway:1 \
  --desired-count 2 \
  --launch-type FARGATE \
  --platform-version LATEST \
  --network-configuration "awsvpcConfiguration={subnets=[subnet-private-a],securityGroups=[sg-ecs-xxx],assignPublicIp=DISABLED}" \
  --load-balancers "targetGroupArn=arn:aws:elasticloadbalancing:REGION:ACCOUNT:targetgroup/mcp-gateway-tg/xxx,containerName=mcp-gateway,containerPort=4444" \
  --health-check-grace-period-seconds 120 \
  --deployment-configuration "minimumHealthyPercent=100,maximumPercent=200,deploymentCircuitBreaker={enable=true,rollback=true}" \
  --enable-execute-command \
  --tags key=Environment,value=production
```

### 5.6 Configure Auto Scaling

```bash
# Register scalable target (N+1 baseline: 2 tasks minimum for redundancy)
aws application-autoscaling register-scalable-target \
  --service-namespace ecs \
  --resource-id service/mcp-gateway-cluster/mcp-gateway \
  --scalable-dimension ecs:service:DesiredCount \
  --min-capacity 2 \
  --max-capacity 8

# Create CPU scaling policy (scale out at 70%, conservative to maintain headroom)
aws application-autoscaling put-scaling-policy \
  --service-namespace ecs \
  --resource-id service/mcp-gateway-cluster/mcp-gateway \
  --scalable-dimension ecs:service:DesiredCount \
  --policy-name mcp-gateway-cpu-scaling \
  --policy-type TargetTrackingScaling \
  --target-tracking-scaling-policy-configuration '{
    "TargetValue": 70.0,
    "PredefinedMetricSpecification": {
      "PredefinedMetricType": "ECSServiceAverageCPUUtilization"
    },
    "ScaleInCooldown": 300,
    "ScaleOutCooldown": 60
  }'

# Create memory scaling policy
aws application-autoscaling put-scaling-policy \
  --service-namespace ecs \
  --resource-id service/mcp-gateway-cluster/mcp-gateway \
  --scalable-dimension ecs:service:DesiredCount \
  --policy-name mcp-gateway-memory-scaling \
  --policy-type TargetTrackingScaling \
  --target-tracking-scaling-policy-configuration '{
    "TargetValue": 70.0,
    "PredefinedMetricSpecification": {
      "PredefinedMetricType": "ECSServiceAverageMemoryUtilization"
    },
    "ScaleInCooldown": 300,
    "ScaleOutCooldown": 60
  }'
```

---

## 6. SSO Configuration

### 6.1 Microsoft Entra ID (Azure AD) Setup

MCP Gateway supports enterprise SSO via OIDC. For Microsoft Entra ID:

1. **Register Application in Azure Portal:**
   - Navigate to Microsoft Entra ID > App registrations > New registration
   - Set redirect URI: `https://mcp-gateway.dev.pop-platform.liatr.io/auth/sso/callback/entra`
   - Note the Application (client) ID and Directory (tenant) ID

2. **Create Client Secret:**
   - Certificates & secrets > New client secret
   - Store in AWS Secrets Manager

3. **Configure API Permissions:**
   - Add `User.Read`, `profile`, `email` permissions
   - Grant admin consent

4. **Update Secrets Manager:**
```bash
aws secretsmanager update-secret \
  --secret-id mcp-gateway/sso \
  --secret-string '{
    "SSO_ENABLED": "true",
    "SSO_ENTRA_ENABLED": "true",
    "SSO_ENTRA_CLIENT_ID": "<client-id>",
    "SSO_ENTRA_CLIENT_SECRET": "<client-secret>",
    "SSO_ENTRA_TENANT_ID": "<tenant-id>",
    "SSO_TRUSTED_DOMAINS": "[\"example.com\"]",
    "SSO_AUTO_CREATE_USERS": "true"
  }'
```

5. **Update Task Definition** to include SSO secrets.

### 6.2 Alternative SSO Providers

MCP Gateway also supports:
- **GitHub OAuth** - For developer organizations
- **Google OAuth** - For Google Workspace
- **Okta** - Enterprise identity provider
- **Keycloak** - Self-hosted OIDC
- **Generic OIDC** - Any OIDC-compliant provider

---

## 7. Observability

### 7.1 CloudWatch Container Insights

Container Insights is enabled during cluster creation. View metrics in CloudWatch:
- CPU/Memory utilization per task
- Network I/O
- Container instance count

### 7.2 CloudWatch Logs

Create log group with retention:
```bash
aws logs create-log-group \
  --log-group-name /aws/ecs/mcp-gateway

aws logs put-retention-policy \
  --log-group-name /aws/ecs/mcp-gateway \
  --retention-in-days 30
```

### 7.3 CloudWatch Alarms

```bash
# High CPU alarm
aws cloudwatch put-metric-alarm \
  --alarm-name "mcp-gateway-high-cpu" \
  --alarm-description "ECS CPU utilization exceeds 80%" \
  --metric-name "CPUUtilization" \
  --namespace "AWS/ECS" \
  --statistic "Average" \
  --period 300 \
  --threshold 80 \
  --comparison-operator "GreaterThanThreshold" \
  --evaluation-periods 2 \
  --dimensions Name=ClusterName,Value=mcp-gateway-cluster Name=ServiceName,Value=mcp-gateway \
  --alarm-actions arn:aws:sns:REGION:ACCOUNT:alerts

# High error rate alarm
aws cloudwatch put-metric-alarm \
  --alarm-name "mcp-gateway-high-error-rate" \
  --alarm-description "ALB 5xx error rate exceeds 5%" \
  --metric-name "HTTPCode_Target_5XX_Count" \
  --namespace "AWS/ApplicationELB" \
  --statistic "Sum" \
  --period 300 \
  --threshold 50 \
  --comparison-operator "GreaterThanThreshold" \
  --evaluation-periods 2 \
  --dimensions Name=LoadBalancer,Value=app/mcp-gateway-alb/xxx \
  --alarm-actions arn:aws:sns:REGION:ACCOUNT:alerts

# Unhealthy task count alarm
aws cloudwatch put-metric-alarm \
  --alarm-name "mcp-gateway-unhealthy-tasks" \
  --alarm-description "Unhealthy target count exceeds 0" \
  --metric-name "UnHealthyHostCount" \
  --namespace "AWS/ApplicationELB" \
  --statistic "Average" \
  --period 60 \
  --threshold 0 \
  --comparison-operator "GreaterThanThreshold" \
  --evaluation-periods 2 \
  --dimensions Name=TargetGroup,Value=targetgroup/mcp-gateway-tg/xxx Name=LoadBalancer,Value=app/mcp-gateway-alb/xxx \
  --alarm-actions arn:aws:sns:REGION:ACCOUNT:alerts
```

### 7.4 CloudWatch Dashboard

```bash
aws cloudwatch put-dashboard \
  --dashboard-name mcp-gateway \
  --dashboard-body '{
    "widgets": [
      {
        "type": "metric",
        "x": 0, "y": 0, "width": 12, "height": 6,
        "properties": {
          "title": "ECS Task Count",
          "metrics": [
            ["AWS/ECS", "RunningTaskCount", "ClusterName", "mcp-gateway-cluster", "ServiceName", "mcp-gateway"]
          ],
          "period": 60
        }
      },
      {
        "type": "metric",
        "x": 12, "y": 0, "width": 12, "height": 6,
        "properties": {
          "title": "CPU & Memory Utilization",
          "metrics": [
            ["AWS/ECS", "CPUUtilization", "ClusterName", "mcp-gateway-cluster", "ServiceName", "mcp-gateway"],
            ["AWS/ECS", "MemoryUtilization", "ClusterName", "mcp-gateway-cluster", "ServiceName", "mcp-gateway"]
          ],
          "period": 60
        }
      },
      {
        "type": "metric",
        "x": 0, "y": 6, "width": 12, "height": 6,
        "properties": {
          "title": "ALB Request Count",
          "metrics": [
            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", "app/mcp-gateway-alb/xxx"]
          ],
          "period": 60
        }
      },
      {
        "type": "metric",
        "x": 12, "y": 6, "width": 12, "height": 6,
        "properties": {
          "title": "ALB Response Time (p99)",
          "metrics": [
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", "app/mcp-gateway-alb/xxx"]
          ],
          "stat": "p99",
          "period": 60
        }
      },
      {
        "type": "metric",
        "x": 0, "y": 12, "width": 12, "height": 6,
        "properties": {
          "title": "Database Connections",
          "metrics": [
            ["AWS/RDS", "DatabaseConnections", "DBInstanceIdentifier", "mcp-gateway-db"]
          ],
          "period": 60
        }
      },
      {
        "type": "metric",
        "x": 12, "y": 12, "width": 12, "height": 6,
        "properties": {
          "title": "Redis Cache Hit Rate",
          "metrics": [
            ["AWS/ElastiCache", "CacheHitRate", "ReplicationGroupId", "mcp-gateway-redis"]
          ],
          "period": 60
        }
      }
    ]
  }'
```

---

## 8. Backup Strategy

### 8.1 AWS Backup Configuration

```bash
# Create backup vault
aws backup create-backup-vault \
  --backup-vault-name mcp-gateway-vault \
  --encryption-key-arn arn:aws:kms:REGION:ACCOUNT:key/xxx

# Create backup plan
aws backup create-backup-plan \
  --backup-plan '{
    "BackupPlanName": "mcp-gateway-backup",
    "Rules": [
      {
        "RuleName": "DailyBackups",
        "TargetBackupVaultName": "mcp-gateway-vault",
        "ScheduleExpression": "cron(0 5 ? * * *)",
        "StartWindowMinutes": 60,
        "CompletionWindowMinutes": 120,
        "Lifecycle": {
          "DeleteAfterDays": 30
        }
      },
      {
        "RuleName": "WeeklyBackups",
        "TargetBackupVaultName": "mcp-gateway-vault",
        "ScheduleExpression": "cron(0 5 ? * SUN *)",
        "StartWindowMinutes": 60,
        "CompletionWindowMinutes": 180,
        "Lifecycle": {
          "MoveToColdStorageAfterDays": 30,
          "DeleteAfterDays": 365
        }
      }
    ]
  }'
```

### 8.2 RDS Automated Backups

RDS is configured with:
- **Automated daily backups**: 30-day retention
- **Point-in-time recovery**: Up to 5 minutes of data loss
- **Manual snapshots**: Before major changes

### 8.3 ElastiCache Backups

ElastiCache is configured with:
- **Daily automatic backups**: 7-day retention
- **Manual snapshots**: Before major changes

### 8.4 Disaster Recovery

| Component | RTO | RPO | Method |
|-----------|-----|-----|--------|
| RDS PostgreSQL | 1-2 hr | 5 min | Point-in-time recovery from backups |
| ElastiCache Redis | 15 min | 1 day | Daily snapshots |
| ECS Tasks | 2 min | 0 | Fargate auto-replace |
| Application State | N/A | 0 | Stateless design |

> **Note:** Single-AZ deployment has longer RTO. For faster recovery, enable Multi-AZ on RDS and add Redis replica.

---

## 9. Security Hardening

### 9.1 Network Security

```bash
# Enable VPC Flow Logs
aws ec2 create-flow-logs \
  --resource-type VPC \
  --resource-ids vpc-xxx \
  --traffic-type ALL \
  --log-destination-type cloud-watch-logs \
  --log-group-name /aws/vpc/mcp-gateway-flow-logs

# Enable AWS WAF (recommended)
aws wafv2 create-web-acl \
  --name mcp-gateway-waf \
  --scope REGIONAL \
  --default-action Allow={} \
  --visibility-config SampledRequestsEnabled=true,CloudWatchMetricsEnabled=true,MetricName=mcp-gateway-waf \
  --rules '[
    {
      "Name": "AWSManagedRulesCommonRuleSet",
      "Priority": 1,
      "OverrideAction": {"None": {}},
      "Statement": {
        "ManagedRuleGroupStatement": {
          "VendorName": "AWS",
          "Name": "AWSManagedRulesCommonRuleSet"
        }
      },
      "VisibilityConfig": {
        "SampledRequestsEnabled": true,
        "CloudWatchMetricsEnabled": true,
        "MetricName": "CommonRuleSet"
      }
    }
  ]'
```

### 9.2 Security Checklist

- [x] VPC with private subnets for workloads
- [x] Security groups with least-privilege rules
- [x] TLS 1.3 on ALB with strong cipher suites
- [x] KMS encryption for all data at rest
- [x] Secrets Manager for all credentials
- [x] IAM roles with minimal permissions
- [ ] VPC Flow Logs enabled
- [ ] AWS WAF protecting ALB
- [ ] GuardDuty enabled for threat detection
- [ ] CloudTrail logging all API calls
- [x] RDS/ElastiCache in private subnets only
- [x] Production security settings in MCP Gateway

---

## 10. Cost Estimation

### Monthly Cost Breakdown (us-east-1, Single AZ)

| Service | Configuration | Monthly Cost |
|---------|--------------|--------------|
| ECS Fargate | 2 tasks × 0.5 vCPU × 1 GB (baseline) | ~$30 |
| RDS PostgreSQL | db.t4g.micro, Single-AZ, 20GB | ~$15 |
| ElastiCache Redis | cache.t4g.micro × 1 node | ~$12 |
| ALB | 1 ALB + LCU | ~$20 |
| NAT Gateway | 1 gateway + data transfer | ~$35 |
| Secrets Manager | 5 secrets + API calls | ~$5 |
| CloudWatch | Logs + metrics | ~$20 |
| AWS Backup | Storage | ~$5 |
| **Total** | | **~$142/month** |

**Scaling Cost Impact:**

- Baseline (2 tasks): ~$30/month for compute
- At 4 tasks: ~$60/month for compute
- At 8 tasks (max): ~$120/month for compute

**Upgrade Path to Production HA (Multi-AZ):**

| Change | Additional Cost |
|--------|-----------------|
| Add 2nd NAT Gateway | +$35/month |
| RDS Multi-AZ | +$15/month |
| ElastiCache replica | +$12/month |
| **Total for HA** | **~$204/month** |

**Comparison to EKS:**

| | ECS Fargate | EKS Fargate |
|--|-------------|-------------|
| Control plane | $0 | $73/month |
| Complexity | Low | High |
| Setup time | Hours | Days |
| K8s expertise | Not required | Required |

---

## 11. Deployment Steps

### Phase 1: Foundation (Day 1)
1. Create VPC with public/private subnets
2. Set up NAT Gateways
3. Create security groups
4. Create KMS keys for encryption
5. Request ACM certificate

### Phase 2: Data Layer (Day 1-2)
1. Deploy RDS PostgreSQL
2. Deploy ElastiCache Redis
3. Configure Secrets Manager
4. Set up AWS Backup

### Phase 3: Compute Layer (Day 2)
1. Create ECS cluster
2. Create IAM roles
3. Create task definition
4. Create ALB and target group
5. Create ECS service

### Phase 4: Scaling & Monitoring (Day 3)
1. Configure auto-scaling policies
2. Set up CloudWatch alarms
3. Create CloudWatch dashboard
4. Enable Container Insights

### Phase 5: Security (Day 3)
1. Enable VPC Flow Logs
2. Configure AWS WAF
3. Enable GuardDuty
4. Verify security group rules

### Phase 6: SSO & Validation (Day 4)
1. Configure SSO provider (if using)
2. Run health checks
3. Test failover scenarios
4. Document runbooks

---

## 12. Maintenance and Operations

### Routine Tasks

| Task | Frequency | Method |
|------|-----------|--------|
| Review CloudWatch alarms | Daily | Dashboard |
| Check backup status | Weekly | AWS Backup console |
| Review container logs | Weekly | CloudWatch Logs Insights |
| Rotate secrets | Quarterly | Secrets Manager rotation |
| Update container image | As needed | ECS deployment |
| RDS minor version updates | Quarterly | Maintenance window |
| Security patching | Monthly | ECS deployment |

### Useful Commands

```bash
# View running tasks
aws ecs list-tasks --cluster mcp-gateway-cluster --service-name mcp-gateway

# Force new deployment (rolling update)
aws ecs update-service --cluster mcp-gateway-cluster --service-name mcp-gateway --force-new-deployment

# View task logs
aws logs tail /aws/ecs/mcp-gateway --follow

# Execute command in running container (for debugging)
aws ecs execute-command \
  --cluster mcp-gateway-cluster \
  --task <task-id> \
  --container mcp-gateway \
  --interactive \
  --command "/bin/sh"

# Scale manually
aws ecs update-service --cluster mcp-gateway-cluster --service-name mcp-gateway --desired-count 4
```

---

## Appendix A: Terraform Usage

**Prerequisites:**

- Terraform >= 1.5.0
- AWS CLI configured with `liatrio` profile
- Access to AWS account 008971644846

**Initialize and Deploy:**

```bash
cd infrastructure

# Initialize Terraform
terraform init

# Plan changes
AWS_PROFILE=liatrio terraform plan -out=tfplan

# Apply changes
AWS_PROFILE=liatrio terraform apply tfplan
```

**Backend Configuration (recommended for team use):**

```hcl
# infrastructure/backend.tf
terraform {
  backend "s3" {
    bucket         = "liatrio-terraform-state"
    key            = "mcp-gateway/terraform.tfstate"
    region         = "us-east-2"
    encrypt        = true
    dynamodb_table = "terraform-locks"
  }
}
```

---

## Appendix B: CI/CD with GitHub Actions

Example workflow for automated deployments:

```yaml
# .github/workflows/deploy.yml
name: Deploy to ECS

on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: us-east-1

      - name: Login to Amazon ECR
        id: login-ecr
        uses: aws-actions/amazon-ecr-login@v2

      - name: Build and push image
        env:
          ECR_REGISTRY: ${{ steps.login-ecr.outputs.registry }}
          IMAGE_TAG: ${{ github.sha }}
        run: |
          docker build -t $ECR_REGISTRY/mcp-gateway:$IMAGE_TAG .
          docker push $ECR_REGISTRY/mcp-gateway:$IMAGE_TAG

      - name: Update ECS service
        run: |
          aws ecs update-service \
            --cluster mcp-gateway-cluster \
            --service mcp-gateway \
            --force-new-deployment
```

---

## Revision History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2025-12-17 | Platform Team | Initial deployment plan |
| 1.1 | 2025-12-17 | Platform Team | Switched from EKS to ECS Fargate |
