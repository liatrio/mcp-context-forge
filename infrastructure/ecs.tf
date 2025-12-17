# -----------------------------------------------------------------------------
# ECS Cluster - Using community module
# -----------------------------------------------------------------------------

module "ecs_cluster" {
  source  = "terraform-aws-modules/ecs/aws//modules/cluster"
  version = "~> 5.0"

  cluster_name = "${local.name}-cluster"

  # Fargate capacity providers
  fargate_capacity_providers = {
    FARGATE = {
      default_capacity_provider_strategy = {
        weight = 1
        base   = 1
      }
    }
    FARGATE_SPOT = {
      default_capacity_provider_strategy = {
        weight = 0
      }
    }
  }

  # Container Insights
  cluster_settings = var.enable_container_insights ? {
    name  = "containerInsights"
    value = "enabled"
  } : null

  tags = local.tags
}

# -----------------------------------------------------------------------------
# Locals for conditional SSO configuration
# -----------------------------------------------------------------------------

locals {
  # Base secrets that are always required
  base_secrets = [
    {
      name      = "DATABASE_URL"
      valueFrom = aws_secretsmanager_secret.database_url.arn
    },
    {
      name      = "JWT_SECRET_KEY"
      valueFrom = "${aws_secretsmanager_secret.app_secrets.arn}:JWT_SECRET_KEY::"
    },
    {
      name      = "AUTH_ENCRYPTION_SECRET"
      valueFrom = "${aws_secretsmanager_secret.app_secrets.arn}:AUTH_ENCRYPTION_SECRET::"
    },
    {
      name      = "BASIC_AUTH_USER"
      valueFrom = "${aws_secretsmanager_secret.app_secrets.arn}:BASIC_AUTH_USER::"
    },
    {
      name      = "BASIC_AUTH_PASSWORD"
      valueFrom = "${aws_secretsmanager_secret.app_secrets.arn}:BASIC_AUTH_PASSWORD::"
    },
    {
      name      = "PLATFORM_ADMIN_EMAIL"
      valueFrom = "${aws_secretsmanager_secret.app_secrets.arn}:PLATFORM_ADMIN_EMAIL::"
    },
    {
      name      = "PLATFORM_ADMIN_PASSWORD"
      valueFrom = "${aws_secretsmanager_secret.app_secrets.arn}:PLATFORM_ADMIN_PASSWORD::"
    },
  ]

  # SSO secrets (only when SSO is enabled)
  sso_secrets = var.sso_enabled ? [
    {
      name      = "SSO_ENABLED"
      valueFrom = "${aws_secretsmanager_secret.sso_secrets[0].arn}:SSO_ENABLED::"
    },
    {
      name      = "SSO_AUTO_CREATE_USERS"
      valueFrom = "${aws_secretsmanager_secret.sso_secrets[0].arn}:SSO_AUTO_CREATE_USERS::"
    },
    {
      name      = "SSO_PRESERVE_ADMIN_AUTH"
      valueFrom = "${aws_secretsmanager_secret.sso_secrets[0].arn}:SSO_PRESERVE_ADMIN_AUTH::"
    },
    {
      name      = "SSO_TRUSTED_DOMAINS"
      valueFrom = "${aws_secretsmanager_secret.sso_secrets[0].arn}:SSO_TRUSTED_DOMAINS::"
    },
    {
      name      = "SSO_GITHUB_ENABLED"
      valueFrom = "${aws_secretsmanager_secret.sso_secrets[0].arn}:SSO_GITHUB_ENABLED::"
    },
    {
      name      = "SSO_GITHUB_CLIENT_ID"
      valueFrom = "${aws_secretsmanager_secret.sso_secrets[0].arn}:SSO_GITHUB_CLIENT_ID::"
    },
    {
      name      = "SSO_GITHUB_CLIENT_SECRET"
      valueFrom = "${aws_secretsmanager_secret.sso_secrets[0].arn}:SSO_GITHUB_CLIENT_SECRET::"
    },
    {
      name      = "SSO_GITHUB_ADMIN_ORGS"
      valueFrom = "${aws_secretsmanager_secret.sso_secrets[0].arn}:SSO_GITHUB_ADMIN_ORGS::"
    },
    {
      name      = "SSO_GITHUB_SCOPE"
      valueFrom = "${aws_secretsmanager_secret.sso_secrets[0].arn}:SSO_GITHUB_SCOPE::"
    },
    {
      name      = "SSO_ENTRA_ENABLED"
      valueFrom = "${aws_secretsmanager_secret.sso_secrets[0].arn}:SSO_ENTRA_ENABLED::"
    },
    {
      name      = "SSO_ENTRA_CLIENT_ID"
      valueFrom = "${aws_secretsmanager_secret.sso_secrets[0].arn}:SSO_ENTRA_CLIENT_ID::"
    },
    {
      name      = "SSO_ENTRA_CLIENT_SECRET"
      valueFrom = "${aws_secretsmanager_secret.sso_secrets[0].arn}:SSO_ENTRA_CLIENT_SECRET::"
    },
    {
      name      = "SSO_ENTRA_TENANT_ID"
      valueFrom = "${aws_secretsmanager_secret.sso_secrets[0].arn}:SSO_ENTRA_TENANT_ID::"
    },
  ] : []

  # Combined secrets
  all_secrets = concat(local.base_secrets, local.sso_secrets)
}

# -----------------------------------------------------------------------------
# CloudWatch Log Group for ECS
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "ecs" {
  name              = "/aws/ecs/${local.name}"
  retention_in_days = var.log_retention_days
  kms_key_id        = aws_kms_key.main.arn

  tags = local.tags
}

# -----------------------------------------------------------------------------
# ECS Task Definition
# -----------------------------------------------------------------------------

resource "aws_ecs_task_definition" "app" {
  family                   = local.name
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name      = "mcp-gateway"
      image     = var.container_image
      essential = true

      portMappings = [
        {
          containerPort = var.container_port
          protocol      = "tcp"
        }
      ]

      environment = [
        { name = "HOST", value = "0.0.0.0" },
        { name = "PORT", value = tostring(var.container_port) },
        { name = "GUNICORN_WORKERS", value = tostring(var.gunicorn_workers) },
        { name = "GUNICORN_TIMEOUT", value = "600" },
        { name = "GUNICORN_MAX_REQUESTS", value = "10000" },
        { name = "GUNICORN_PRELOAD_APP", value = "true" },
        { name = "DB_POOL_SIZE", value = "10" },
        { name = "DB_MAX_OVERFLOW", value = "20" },
        { name = "DB_POOL_TIMEOUT", value = "60" },
        { name = "DB_POOL_RECYCLE", value = "1800" },
        { name = "DB_POOL_PRE_PING", value = "true" },
        { name = "CACHE_TYPE", value = "redis" },
        { name = "CACHE_PREFIX", value = "mcpgw:" },
        { name = "SESSION_TTL", value = "3600" },
        { name = "MESSAGE_TTL", value = "600" },
        { name = "ENVIRONMENT", value = "production" },
        { name = "APP_DOMAIN", value = "https://${var.domain_name}" },
        { name = "MCPGATEWAY_UI_ENABLED", value = tostring(var.admin_ui_enabled) },
        { name = "MCPGATEWAY_ADMIN_API_ENABLED", value = tostring(var.admin_api_enabled) },
        { name = "AUTH_REQUIRED", value = "true" },
        { name = "SECURE_COOKIES", value = "true" },
        { name = "COOKIE_SAMESITE", value = "strict" },
        { name = "LOG_LEVEL", value = var.log_level },
        { name = "LOG_FORMAT", value = "json" },
        { name = "OTEL_ENABLE_OBSERVABILITY", value = "true" },
        { name = "OTEL_SERVICE_NAME", value = var.project_name },
        { name = "REDIS_URL", value = "redis://${aws_elasticache_cluster.redis.cache_nodes[0].address}:6379" },
        { name = "PLUGINS_ENABLED", value = "true" },
      ]

      # Secrets are managed in locals block above (base_secrets + sso_secrets)
      secrets = local.all_secrets

      healthCheck = {
        command     = ["CMD-SHELL", "curl -f http://localhost:${var.container_port}/health || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 60
      }

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "mcp-gateway"
        }
      }
    }
  ])

  tags = local.tags
}

# -----------------------------------------------------------------------------
# ECS Service
# -----------------------------------------------------------------------------

resource "aws_ecs_service" "app" {
  name            = local.name
  cluster         = module.ecs_cluster.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = module.vpc.private_subnets
    security_groups  = [module.ecs_sg.security_group_id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = module.alb.target_groups["ecs"].arn
    container_name   = "mcp-gateway"
    container_port   = var.container_port
  }

  # Health check grace period for slow startups
  health_check_grace_period_seconds = 120

  # Deployment configuration for rolling updates
  deployment_maximum_percent         = 200
  deployment_minimum_healthy_percent = 100

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  # Enable ECS Exec for debugging
  enable_execute_command = true

  # Ensure ALB target group is created first
  depends_on = [module.alb]

  # Ignore desired_count changes from auto-scaling
  lifecycle {
    ignore_changes = [desired_count]
  }

  tags = local.tags
}

# -----------------------------------------------------------------------------
# Auto Scaling
# -----------------------------------------------------------------------------

resource "aws_appautoscaling_target" "ecs" {
  max_capacity       = var.max_capacity
  min_capacity       = var.min_capacity
  resource_id        = "service/${module.ecs_cluster.name}/${aws_ecs_service.app.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

# CPU-based scaling policy
resource "aws_appautoscaling_policy" "cpu" {
  name               = "${local.name}-cpu-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }

    target_value       = var.cpu_target_value
    scale_in_cooldown  = 300
    scale_out_cooldown = 60
  }
}

# Memory-based scaling policy
resource "aws_appautoscaling_policy" "memory" {
  name               = "${local.name}-memory-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageMemoryUtilization"
    }

    target_value       = var.memory_target_value
    scale_in_cooldown  = 300
    scale_out_cooldown = 60
  }
}
