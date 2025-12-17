# -----------------------------------------------------------------------------
# Data Sources
# -----------------------------------------------------------------------------

data "aws_caller_identity" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  account_id = data.aws_caller_identity.current.account_id
  name       = "${var.project_name}-${var.environment}"

  # Use specified AZ for single-AZ deployment, but need 2 AZs for RDS subnet group
  azs = [
    var.availability_zone,
    data.aws_availability_zones.available.names[1]
  ]

  # Resource-specific tags (merged with provider default_tags automatically)
  # Use these to add component-level identification
  tags = {
    # Component tags are inherited; add resource-specific overrides here if needed
  }
}

# -----------------------------------------------------------------------------
# VPC - Using community module
# -----------------------------------------------------------------------------

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${local.name}-vpc"
  cidr = var.vpc_cidr

  azs              = local.azs
  public_subnets   = var.public_subnet_cidrs
  private_subnets  = [var.private_subnet_cidr]
  database_subnets = var.database_subnet_cidrs

  # Single NAT Gateway for cost savings
  enable_nat_gateway     = true
  single_nat_gateway     = true
  one_nat_gateway_per_az = false

  # DNS settings for private hosted zones
  enable_dns_hostnames = true
  enable_dns_support   = true

  # Database subnet group for RDS
  create_database_subnet_group       = true
  create_database_subnet_route_table = true
  database_subnet_group_name         = "${local.name}-db-subnet"

  tags = local.tags
}

# -----------------------------------------------------------------------------
# Security Groups - Using community module
# -----------------------------------------------------------------------------

# ALB Security Group
module "alb_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 5.0"

  name        = "${local.name}-alb-sg"
  description = "Security group for Application Load Balancer"
  vpc_id      = module.vpc.vpc_id

  ingress_cidr_blocks = ["0.0.0.0/0"]
  ingress_rules       = ["https-443-tcp", "http-80-tcp"]

  egress_rules = ["all-all"]

  tags = local.tags
}

# ECS Tasks Security Group
module "ecs_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 5.0"

  name        = "${local.name}-ecs-sg"
  description = "Security group for ECS tasks"
  vpc_id      = module.vpc.vpc_id

  ingress_with_source_security_group_id = [
    {
      from_port                = var.container_port
      to_port                  = var.container_port
      protocol                 = "tcp"
      description              = "Allow traffic from ALB"
      source_security_group_id = module.alb_sg.security_group_id
    }
  ]

  egress_rules = ["all-all"]

  tags = local.tags
}

# RDS Security Group
module "rds_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 5.0"

  name        = "${local.name}-rds-sg"
  description = "Security group for RDS PostgreSQL"
  vpc_id      = module.vpc.vpc_id

  ingress_with_source_security_group_id = [
    {
      from_port                = 5432
      to_port                  = 5432
      protocol                 = "tcp"
      description              = "Allow PostgreSQL from ECS tasks"
      source_security_group_id = module.ecs_sg.security_group_id
    }
  ]

  egress_rules = ["all-all"]

  tags = local.tags
}

# Redis Security Group
module "redis_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 5.0"

  name        = "${local.name}-redis-sg"
  description = "Security group for ElastiCache Redis"
  vpc_id      = module.vpc.vpc_id

  ingress_with_source_security_group_id = [
    {
      from_port                = 6379
      to_port                  = 6379
      protocol                 = "tcp"
      description              = "Allow Redis from ECS tasks"
      source_security_group_id = module.ecs_sg.security_group_id
    }
  ]

  egress_rules = ["all-all"]

  tags = local.tags
}

# -----------------------------------------------------------------------------
# ACM Certificate - Using community module
# -----------------------------------------------------------------------------

module "acm" {
  source  = "terraform-aws-modules/acm/aws"
  version = "~> 5.0"

  domain_name = var.domain_name
  zone_id     = var.route53_zone_id

  validation_method   = "DNS"
  wait_for_validation = true

  tags = local.tags
}

# -----------------------------------------------------------------------------
# Application Load Balancer - Using community module
# -----------------------------------------------------------------------------

module "alb" {
  source  = "terraform-aws-modules/alb/aws"
  version = "~> 9.0"

  name               = "${local.name}-alb"
  load_balancer_type = "application"

  vpc_id  = module.vpc.vpc_id
  subnets = module.vpc.public_subnets

  security_groups = [module.alb_sg.security_group_id]

  # Enable deletion protection in production
  enable_deletion_protection = var.environment == "production"

  listeners = {
    https = {
      port            = 443
      protocol        = "HTTPS"
      certificate_arn = module.acm.acm_certificate_arn
      ssl_policy      = "ELBSecurityPolicy-TLS13-1-2-2021-06"

      forward = {
        target_group_key = "ecs"
      }
    }

    http = {
      port     = 80
      protocol = "HTTP"

      redirect = {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }
  }

  target_groups = {
    ecs = {
      name             = "${local.name}-tg"
      backend_protocol = "HTTP"
      backend_port     = var.container_port
      target_type      = "ip"

      health_check = {
        enabled             = true
        healthy_threshold   = 2
        unhealthy_threshold = 3
        timeout             = 5
        interval            = 30
        path                = "/health"
        protocol            = "HTTP"
        matcher             = "200"
      }

      # Required for Fargate
      create_attachment = false
    }
  }

  tags = local.tags
}

# -----------------------------------------------------------------------------
# Route53 DNS Record
# -----------------------------------------------------------------------------

resource "aws_route53_record" "app" {
  zone_id = var.route53_zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = module.alb.dns_name
    zone_id                = module.alb.zone_id
    evaluate_target_health = true
  }
}

# -----------------------------------------------------------------------------
# RDS PostgreSQL - Using community module
# -----------------------------------------------------------------------------

module "rds" {
  source  = "terraform-aws-modules/rds/aws"
  version = "~> 6.0"

  identifier = "${local.name}-db"

  engine               = "postgres"
  engine_version       = var.db_engine_version
  family               = "postgres16"
  major_engine_version = "16"
  instance_class       = var.db_instance_class

  allocated_storage     = var.db_allocated_storage
  max_allocated_storage = var.db_max_allocated_storage
  storage_type          = "gp3"
  storage_encrypted     = true

  db_name  = var.db_name
  username = var.db_username
  port     = 5432

  # Use Secrets Manager for master password
  manage_master_user_password                            = true
  manage_master_user_password_rotation                   = true
  master_user_password_rotate_immediately                = false
  master_user_password_rotation_automatically_after_days = 30

  multi_az               = var.db_multi_az
  db_subnet_group_name   = module.vpc.database_subnet_group_name
  vpc_security_group_ids = [module.rds_sg.security_group_id]

  # Maintenance and backups
  maintenance_window               = "Mon:00:00-Mon:03:00"
  backup_window                    = "03:00-06:00"
  backup_retention_period          = var.db_backup_retention_period
  skip_final_snapshot              = false
  final_snapshot_identifier_prefix = "${local.name}-final"
  deletion_protection              = var.db_deletion_protection
  copy_tags_to_snapshot            = true
  auto_minor_version_upgrade       = true
  apply_immediately                = false

  # Performance Insights (free tier)
  performance_insights_enabled          = true
  performance_insights_retention_period = 7

  # Enhanced monitoring
  monitoring_interval = 60
  monitoring_role_arn = aws_iam_role.rds_monitoring.arn

  # Parameter group with optimized settings
  # db.t4g.small has 2GB RAM, can support ~150 connections safely
  parameters = [
    {
      name         = "max_connections"
      value        = "150"
      apply_method = "pending-reboot"
    }
  ]

  tags = local.tags
}

# RDS Enhanced Monitoring IAM Role
resource "aws_iam_role" "rds_monitoring" {
  name = "${local.name}-rds-monitoring"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "monitoring.rds.amazonaws.com"
        }
      }
    ]
  })

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  role       = aws_iam_role.rds_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# -----------------------------------------------------------------------------
# ElastiCache Redis
# -----------------------------------------------------------------------------

resource "aws_elasticache_subnet_group" "redis" {
  name       = "${local.name}-redis-subnet"
  subnet_ids = module.vpc.private_subnets

  tags = local.tags
}

resource "aws_elasticache_cluster" "redis" {
  cluster_id           = "${local.name}-redis"
  engine               = "redis"
  engine_version       = var.redis_engine_version
  node_type            = var.redis_node_type
  num_cache_nodes      = var.redis_num_cache_nodes
  port                 = 6379
  parameter_group_name = "default.redis7"

  subnet_group_name  = aws_elasticache_subnet_group.redis.name
  security_group_ids = [module.redis_sg.security_group_id]

  # Backups
  snapshot_retention_limit = var.redis_snapshot_retention_limit
  snapshot_window          = "05:00-09:00"
  maintenance_window       = "mon:10:00-mon:11:00"

  # Note: transit_encryption_enabled requires auth_token which requires replication group
  # For single-node deployment, we rely on VPC security

  apply_immediately = false

  tags = local.tags
}

# -----------------------------------------------------------------------------
# KMS Key for encryption
# -----------------------------------------------------------------------------

resource "aws_kms_key" "main" {
  description             = "KMS key for ${local.name} encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  # KMS key policy allowing CloudWatch Logs to use the key
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${local.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow CloudWatch Logs"
        Effect = "Allow"
        Principal = {
          Service = "logs.${var.aws_region}.amazonaws.com"
        }
        Action = [
          "kms:Encrypt*",
          "kms:Decrypt*",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:Describe*"
        ]
        Resource = "*"
        Condition = {
          ArnLike = {
            "kms:EncryptionContext:aws:logs:arn" = "arn:aws:logs:${var.aws_region}:${local.account_id}:*"
          }
        }
      }
    ]
  })

  tags = local.tags
}

resource "aws_kms_alias" "main" {
  name          = "alias/${local.name}"
  target_key_id = aws_kms_key.main.key_id
}
