# -----------------------------------------------------------------------------
# General Configuration
# -----------------------------------------------------------------------------

variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-2"
}

variable "aws_profile" {
  description = "AWS CLI profile to use"
  type        = string
  default     = "liatrio"
}

variable "environment" {
  description = "Environment name (dev, staging, production)"
  type        = string
  default     = "dev"
}

variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "mcp-gateway"
}

# -----------------------------------------------------------------------------
# Networking
# -----------------------------------------------------------------------------

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zone" {
  description = "Availability zone for single-AZ deployment"
  type        = string
  default     = "us-east-2a"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets (requires 2 for ALB multi-AZ)"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidr" {
  description = "CIDR block for the private subnet"
  type        = string
  default     = "10.0.10.0/24"
}

variable "database_subnet_cidrs" {
  description = "CIDR blocks for database subnets (requires 2 for RDS subnet group)"
  type        = list(string)
  default     = ["10.0.20.0/24", "10.0.21.0/24"]
}

# -----------------------------------------------------------------------------
# DNS and Domain
# -----------------------------------------------------------------------------

variable "domain_name" {
  description = "Domain name for the application"
  type        = string
  default     = "mcp-gateway.dev.pop-platform.liatr.io"
}

variable "route53_zone_id" {
  description = "Route53 hosted zone ID for DNS records"
  type        = string
  default     = "Z04526022XWDTY6SX40DX"
}

# -----------------------------------------------------------------------------
# ECS Configuration
# -----------------------------------------------------------------------------

variable "container_image" {
  description = "Docker image for MCP Gateway"
  type        = string
  default     = "ghcr.io/ibm/mcp-context-forge:1.0.0-BETA-1"
}

variable "container_port" {
  description = "Port the container listens on"
  type        = number
  default     = 4444
}

variable "task_cpu" {
  description = "CPU units for the ECS task (256 = 0.25 vCPU)"
  type        = number
  default     = 512
}

variable "task_memory" {
  description = "Memory (MB) for the ECS task"
  type        = number
  default     = 1024
}

variable "gunicorn_workers" {
  description = "Number of Gunicorn workers per container"
  type        = number
  default     = 2
}

variable "desired_count" {
  description = "Initial desired count of ECS tasks"
  type        = number
  default     = 2
}

variable "min_capacity" {
  description = "Minimum number of ECS tasks (N+1 baseline)"
  type        = number
  default     = 2
}

variable "max_capacity" {
  description = "Maximum number of ECS tasks"
  type        = number
  default     = 8
}

variable "cpu_target_value" {
  description = "Target CPU utilization percentage for auto-scaling"
  type        = number
  default     = 70
}

variable "memory_target_value" {
  description = "Target memory utilization percentage for auto-scaling"
  type        = number
  default     = 70
}

# -----------------------------------------------------------------------------
# RDS Configuration
# -----------------------------------------------------------------------------

variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t4g.micro"
}

variable "db_allocated_storage" {
  description = "Allocated storage for RDS (GB)"
  type        = number
  default     = 20
}

variable "db_max_allocated_storage" {
  description = "Maximum allocated storage for RDS auto-scaling (GB)"
  type        = number
  default     = 100
}

variable "db_engine_version" {
  description = "PostgreSQL engine version"
  type        = string
  default     = "16.6"
}

variable "db_name" {
  description = "Name of the database"
  type        = string
  default     = "mcpgateway"
}

variable "db_username" {
  description = "Master username for the database"
  type        = string
  default     = "mcpgateway"
}

variable "db_backup_retention_period" {
  description = "Backup retention period in days"
  type        = number
  default     = 7
}

variable "db_multi_az" {
  description = "Enable Multi-AZ for RDS (adds cost but improves HA)"
  type        = bool
  default     = false
}

variable "db_deletion_protection" {
  description = "Enable deletion protection for RDS"
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# ElastiCache Configuration
# -----------------------------------------------------------------------------

variable "redis_node_type" {
  description = "ElastiCache node type"
  type        = string
  default     = "cache.t4g.micro"
}

variable "redis_engine_version" {
  description = "Redis engine version"
  type        = string
  default     = "7.1"
}

variable "redis_num_cache_nodes" {
  description = "Number of cache nodes (1 for single node, 2+ for replication)"
  type        = number
  default     = 1
}

variable "redis_snapshot_retention_limit" {
  description = "Number of days to retain automatic snapshots"
  type        = number
  default     = 3
}

# -----------------------------------------------------------------------------
# Application Configuration
# -----------------------------------------------------------------------------

variable "basic_auth_user" {
  description = "Basic auth username for the application"
  type        = string
  default     = "admin"
}

variable "platform_admin_email" {
  description = "Email for the platform admin user"
  type        = string
}

variable "log_level" {
  description = "Application log level"
  type        = string
  default     = "INFO"
}

variable "admin_ui_enabled" {
  description = "Enable the Admin UI"
  type        = bool
  default     = true
}

variable "admin_api_enabled" {
  description = "Enable the Admin API"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 30
}

# -----------------------------------------------------------------------------
# SSO Configuration (Optional)
# -----------------------------------------------------------------------------

variable "sso_enabled" {
  description = "Enable SSO authentication"
  type        = bool
  default     = false
}

# GitHub OAuth Configuration
variable "sso_github_enabled" {
  description = "Enable GitHub OAuth SSO"
  type        = bool
  default     = false
}

variable "sso_github_client_id" {
  description = "GitHub OAuth App client ID"
  type        = string
  default     = ""
  sensitive   = true
}

variable "sso_github_client_secret" {
  description = "GitHub OAuth App client secret"
  type        = string
  default     = ""
  sensitive   = true
}

variable "sso_github_admin_orgs" {
  description = "GitHub organizations whose members get admin privileges (JSON array)"
  type        = list(string)
  default     = []
}

variable "sso_github_scope" {
  description = "GitHub OAuth scopes (space-separated)"
  type        = string
  default     = "user:email read:org"
}

# Microsoft Entra ID Configuration
variable "sso_entra_enabled" {
  description = "Enable Microsoft Entra ID (Azure AD) SSO"
  type        = bool
  default     = false
}

variable "sso_entra_client_id" {
  description = "Microsoft Entra ID client ID"
  type        = string
  default     = ""
  sensitive   = true
}

variable "sso_entra_client_secret" {
  description = "Microsoft Entra ID client secret"
  type        = string
  default     = ""
  sensitive   = true
}

variable "sso_entra_tenant_id" {
  description = "Microsoft Entra ID tenant ID"
  type        = string
  default     = ""
  sensitive   = true
}

# SSO General Settings
variable "sso_trusted_domains" {
  description = "List of trusted email domains for SSO users"
  type        = list(string)
  default     = []
}

variable "sso_auto_create_users" {
  description = "Automatically create users on first SSO login"
  type        = bool
  default     = true
}

variable "sso_preserve_admin_auth" {
  description = "Keep local admin authentication when SSO is enabled"
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# Monitoring Configuration
# -----------------------------------------------------------------------------

variable "enable_container_insights" {
  description = "Enable CloudWatch Container Insights"
  type        = bool
  default     = true
}

variable "alarm_sns_topic_arn" {
  description = "SNS topic ARN for CloudWatch alarms (optional)"
  type        = string
  default     = ""
}

# -----------------------------------------------------------------------------
# Resource Tagging
# -----------------------------------------------------------------------------

variable "owner" {
  description = "Owner name and email for resource ownership (use format: name@email.com or name_email.com)"
  type        = string
  default     = "daniel.hagen@liatrio.com"
}

variable "team" {
  description = "Team responsible for the resources"
  type        = string
  default     = "AI Innovation Squad"
}

variable "cost_center" {
  description = "Cost center for billing allocation"
  type        = string
  default     = "ai-innovation"
}

variable "data_classification" {
  description = "Data classification level (public, internal, confidential, restricted)"
  type        = string
  default     = "internal"
}

variable "public_facing" {
  description = "Whether the application is publicly accessible"
  type        = bool
  default     = true
}

variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
