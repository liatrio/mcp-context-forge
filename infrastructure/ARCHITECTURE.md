# MCP Gateway AWS Architecture

## Deployment Diagram

```
                                    ┌─────────────────────────────────────────────────────────────────────────────────┐
                                    │                              AWS Cloud (us-east-2)                              │
                                    │                            Account: 008971644846                                │
                                    └─────────────────────────────────────────────────────────────────────────────────┘

    ┌──────────────┐                                    ┌─────────────────────────────────────────────────────────────────────────────────┐
    │   Internet   │                                    │                          VPC: 10.0.0.0/16                                       │
    │    Users     │                                    │                                                                                 │
    └──────┬───────┘                                    │  ┌───────────────────────────────────────────────────────────────────────────┐  │
           │                                            │  │                     Public Subnet: 10.0.1.0/24 (us-east-2a)               │  │
           │ HTTPS (443)                                │  │                                                                           │  │
           ▼                                            │  │   ┌─────────────┐        ┌──────────────────────────────────────────┐    │  │
    ┌──────────────┐     DNS                            │  │   │   Internet  │        │     Application Load Balancer (ALB)      │    │  │
    │   Route 53   │◄───────────────────────────────────┼──┼───│   Gateway   │───────►│  mcp-gateway-dev-alb                     │    │  │
    │              │     mcp-gateway.dev.pop-           │  │   └─────────────┘        │  - HTTPS Listener (443)                  │    │  │
    │ Zone: Z045...│     platform.liatr.io              │  │          │               │  - HTTP→HTTPS Redirect (80)              │    │  │
    └──────────────┘                                    │  │          │               │  - TLS 1.3 (ELBSecurityPolicy)           │    │  │
                                                        │  │          ▼               └────────────────────┬─────────────────────┘    │  │
    ┌──────────────┐                                    │  │   ┌─────────────┐                             │                          │  │
    │     ACM      │                                    │  │   │  NAT GW +   │                             │                          │  │
    │ Certificate  │────────────────────────────────────┼──┼──►│  Elastic IP │                             │                          │  │
    │  (DNS Valid) │                                    │  │   └──────┬──────┘                             │                          │  │
    └──────────────┘                                    │  │          │                                    │                          │  │
                                                        │  └──────────┼────────────────────────────────────┼──────────────────────────┘  │
                                                        │             │                                    │                             │
                                                        │  ┌──────────┼────────────────────────────────────┼──────────────────────────┐  │
                                                        │  │          │    Private Subnet: 10.0.10.0/24 (us-east-2a)                  │  │
                                                        │  │          │                                    │                          │  │
                                                        │  │          │                                    ▼                          │  │
                                                        │  │          │         ┌─────────────────────────────────────────────────┐   │  │
                                                        │  │          │         │              ECS Cluster (Fargate)              │   │  │
                                                        │  │          │         │           mcp-gateway-dev-cluster               │   │  │
                                                        │  │          │         │                                                 │   │  │
                                                        │  │          │         │  ┌─────────────────┐  ┌─────────────────┐       │   │  │
                                                        │  │          │         │  │   ECS Task 1    │  │   ECS Task 2    │       │   │  │
                                                        │  │          │         │  │  (mcp-gateway)  │  │  (mcp-gateway)  │       │   │  │
                                                        │  │          │         │  │                 │  │                 │       │   │  │
                                                        │  │          │         │  │ CPU: 0.5 vCPU   │  │ CPU: 0.5 vCPU   │       │   │  │
                                                        │  │          │         │  │ Memory: 1GB     │  │ Memory: 1GB     │       │   │  │
                                                        │  │          │         │  │ Port: 4444      │  │ Port: 4444      │       │   │  │
                                                        │  │          │         │  └────────┬────────┘  └────────┬────────┘       │   │  │
                                                        │  │          │         │           │                    │                │   │  │
                                                        │  │          │         │           └─────────┬──────────┘                │   │  │
                                                        │  │          │         │                     │                           │   │  │
                                                        │  │          │         │  Auto-Scaling: 2-8 tasks (70% CPU/Memory)       │   │  │
                                                        │  │          │         └─────────────────────┼───────────────────────────┘   │  │
                                                        │  │          │                               │                               │  │
                                                        │  │          │                               │                               │  │
                                                        │  │   ┌──────┴─────────────┐                 │                               │  │
                                                        │  │   │  ElastiCache Redis │◄────────────────┘                               │  │
                                                        │  │   │  cache.t4g.micro   │                                                 │  │
                                                        │  │   │  Port: 6379        │                                                 │  │
                                                        │  │   │  Engine: 7.1       │                                                 │  │
                                                        │  │   └────────────────────┘                                                 │  │
                                                        │  │                                                                          │  │
                                                        │  └──────────────────────────────────────────────────────────────────────────┘  │
                                                        │                                                                                │
                                                        │  ┌──────────────────────────────────────────────────────────────────────────┐  │
                                                        │  │            Database Subnets: 10.0.20.0/24, 10.0.21.0/24                  │  │
                                                        │  │                      (us-east-2a, us-east-2b)                            │  │
                                                        │  │                                                                          │  │
                                                        │  │   ┌────────────────────────────────────────────────────────────────┐     │  │
                                                        │  │   │                    RDS PostgreSQL                              │     │  │
                                                        │  │   │                  mcp-gateway-dev-db                            │     │  │
                                                        │  │   │                                                                │     │  │
                                                        │  │   │  Instance: db.t4g.micro    Engine: PostgreSQL 16.4            │     │  │
                                                        │  │   │  Storage: 20-100 GB (gp3)  Port: 5432                         │     │  │
                                                        │  │   │  Encrypted: Yes (KMS)      Multi-AZ: No (single AZ)           │     │  │
                                                        │  │   │  Backups: 7 days           Performance Insights: Enabled      │     │  │
                                                        │  │   │  Deletion Protection: Yes                                     │     │  │
                                                        │  │   └────────────────────────────────────────────────────────────────┘     │  │
                                                        │  │                                                                          │  │
                                                        │  └──────────────────────────────────────────────────────────────────────────┘  │
                                                        │                                                                                │
                                                        └────────────────────────────────────────────────────────────────────────────────┘


┌─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│                                              Supporting AWS Services                                                                    │
├─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                                                                         │
│  ┌────────────────────┐    ┌────────────────────┐    ┌────────────────────┐    ┌────────────────────┐    ┌────────────────────┐        │
│  │   Secrets Manager  │    │        KMS         │    │    CloudWatch      │    │    CloudWatch      │    │   VPC Flow Logs    │        │
│  │                    │    │                    │    │     Dashboard      │    │      Alarms        │    │                    │        │
│  │  • app-secrets     │    │  • Encryption key  │    │                    │    │                    │    │  • Traffic logs    │        │
│  │  • database-url    │    │  • Auto-rotation   │    │  • ECS metrics     │    │  • High CPU        │    │  • Security audit  │        │
│  │  • sso-secrets*    │    │  • All data at     │    │  • RDS metrics     │    │  • High Memory     │    │  • Stored in       │        │
│  │                    │    │    rest encrypted  │    │  • Redis metrics   │    │  • Unhealthy hosts │    │    CloudWatch      │        │
│  │  *when SSO enabled │    │                    │    │  • ALB metrics     │    │  • RDS CPU/Storage │    │                    │        │
│  └────────────────────┘    └────────────────────┘    └────────────────────┘    │  • Redis CPU       │    └────────────────────┘        │
│                                                                                 │  • 5xx errors      │                                  │
│                                                                                 └────────────────────┘                                  │
│                                                                                                                                         │
│  ┌──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐  │
│  │                                              IAM Roles & Policies                                                                │  │
│  │                                                                                                                                  │  │
│  │  • ecs-execution-role: Pull images, access secrets, decrypt KMS                                                                 │  │
│  │  • ecs-task-role: CloudWatch logs, ECS Exec (debugging)                                                                         │  │
│  │  • rds-monitoring-role: Enhanced monitoring                                                                                     │  │
│  │  • vpc-flow-logs-role: Write flow logs to CloudWatch                                                                            │  │
│  └──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘  │
│                                                                                                                                         │
└─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘


┌─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│                                              Security Groups                                                                            │
├─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│                                                                                                                                         │
│  ┌─────────────────┐      ┌─────────────────┐      ┌─────────────────┐      ┌─────────────────┐                                         │
│  │    ALB SG       │      │    ECS SG       │      │    RDS SG       │      │   Redis SG      │                                         │
│  │                 │      │                 │      │                 │      │                 │                                         │
│  │ Ingress:        │      │ Ingress:        │      │ Ingress:        │      │ Ingress:        │                                         │
│  │  • 0.0.0.0/0    │─────►│  • ALB SG       │─────►│  • ECS SG       │      │  • ECS SG       │                                         │
│  │    :80, :443    │      │    :4444        │      │    :5432        │      │    :6379        │                                         │
│  │                 │      │                 │      │                 │      │                 │                                         │
│  │ Egress: All     │      │ Egress: All     │      │ Egress: All     │      │ Egress: All     │                                         │
│  └─────────────────┘      └─────────────────┘      └─────────────────┘      └─────────────────┘                                         │
│                                                                                                                                         │
└─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
```

## Resource Summary

### Terraform Resources Created (82 total)

| Category | Resource Type | Count | Description |
|----------|--------------|-------|-------------|
| **Networking** | VPC | 1 | Main VPC (10.0.0.0/16) |
| | Subnets | 4 | 1 public, 1 private, 2 database |
| | Internet Gateway | 1 | Public internet access |
| | NAT Gateway | 1 | Private subnet outbound |
| | Elastic IP | 1 | For NAT Gateway |
| | Route Tables | 3 | Public, private, database |
| | Security Groups | 4 | ALB, ECS, RDS, Redis |
| **Compute** | ECS Cluster | 1 | Fargate cluster |
| | ECS Service | 1 | Running 2 tasks |
| | Task Definition | 1 | Container config |
| | Auto-Scaling | 3 | Target + 2 policies |
| **Database** | RDS Instance | 1 | PostgreSQL 16.4 |
| | Parameter Group | 1 | DB settings |
| | Subnet Group | 1 | Multi-AZ capable |
| **Caching** | ElastiCache | 1 | Redis 7.1 cluster |
| | Subnet Group | 1 | Redis networking |
| **Load Balancing** | ALB | 1 | Application Load Balancer |
| | Listeners | 2 | HTTPS + HTTP redirect |
| | Target Group | 1 | ECS tasks |
| **DNS & TLS** | Route53 Record | 2 | App + ACM validation |
| | ACM Certificate | 1 | DNS-validated |
| **Security** | KMS Key | 1 | Encryption |
| | Secrets | 2-3 | App, DB, SSO (optional) |
| | IAM Roles | 4 | ECS, RDS, Flow Logs |
| | IAM Policies | 6 | Attached to roles |
| **Monitoring** | CloudWatch Dashboard | 1 | Metrics visualization |
| | CloudWatch Alarms | 7 | CPU, memory, errors |
| | Log Groups | 3 | ECS, VPC, cluster |
| | VPC Flow Logs | 1 | Traffic logging |

## Data Flow

```
User Request Flow:
──────────────────
Internet → Route53 DNS → ALB (HTTPS/443) → ECS Tasks (port 4444) → Response

Internal Service Flow:
──────────────────────
ECS Task → PostgreSQL (RDS :5432) for persistent data
ECS Task → Redis (ElastiCache :6379) for caching/sessions
ECS Task → Secrets Manager for credentials
ECS Task → CloudWatch for logs

Outbound Flow:
──────────────
ECS Task → NAT Gateway → Internet Gateway → External MCP servers
```

## Cost Estimate

| Service | Configuration | Estimated Monthly Cost |
|---------|--------------|------------------------|
| ECS Fargate | 2 tasks × 0.5 vCPU × 1GB | ~$30 |
| RDS PostgreSQL | db.t4g.micro, 20GB | ~$15 |
| ElastiCache Redis | cache.t4g.micro | ~$12 |
| Application Load Balancer | + data transfer | ~$20 |
| NAT Gateway | + data transfer | ~$35 |
| Route53 | Hosted zone queries | ~$1 |
| Secrets Manager | 3 secrets | ~$2 |
| CloudWatch | Logs + metrics | ~$10 |
| KMS | Key usage | ~$1 |
| Data Transfer | Estimated | ~$16 |
| **Total** | | **~$142/month** |

## Deployment Commands

```bash
# Initialize Terraform
cd infrastructure
terraform init

# Review the plan
terraform plan -out=tfplan

# Apply the infrastructure
terraform apply tfplan

# Get outputs (app URL, database endpoint, etc.)
terraform output
```

## Post-Deployment

After `terraform apply` completes:

1. **Access the application**: `https://mcp-gateway.dev.pop-platform.liatr.io`
2. **Get admin credentials**: Check Secrets Manager in AWS Console
3. **View logs**: CloudWatch Log Groups → `/aws/ecs/mcp-gateway-dev`
4. **Monitor**: CloudWatch Dashboard → `mcp-gateway-dev`

## Optional: Enable GitHub SSO

1. Create GitHub OAuth App at https://github.com/settings/developers
2. Set callback URL: `https://mcp-gateway.dev.pop-platform.liatr.io/auth/sso/callback/github`
3. Update `terraform.tfvars`:
   ```hcl
   sso_enabled = true
   sso_github_enabled = true
   sso_github_client_id = "your-client-id"
   sso_github_client_secret = "your-client-secret"
   sso_github_admin_orgs = ["Liatrio"]
   ```
4. Run `terraform apply`
