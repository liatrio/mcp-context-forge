# -----------------------------------------------------------------------------
# CloudWatch Dashboard - Operational Overview
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = local.name

  dashboard_body = jsonencode({
    widgets = [
      # =======================================================================
      # ROW 0: Service Information Panel
      # =======================================================================
      {
        type   = "text"
        x      = 0
        y      = 0
        width  = 12
        height = 10
        properties = {
          markdown = <<-EOT
## MCP Gateway (ContextForge)

**Description:** Production-grade gateway, proxy, and registry for Model Context Protocol (MCP) servers and A2A Agents. Federates MCP and REST services with unified discovery, auth, rate-limiting, and observability.

**Application URL:** [https://${var.domain_name}](https://${var.domain_name})

**Environment:** `${var.environment}` | **Region:** `${var.aws_region}` | **Data Classification:** `${var.data_classification}`

**Infrastructure:**
| Component | Configuration |
|---|---|
| **ECS Tasks** | ${var.min_capacity}-${var.max_capacity} tasks (${var.task_cpu} CPU / ${var.task_memory} MB) |
| **RDS PostgreSQL** | ${var.db_instance_class} (${var.db_allocated_storage}-${var.db_max_allocated_storage} GB, max ${150} connections) |
| **ElastiCache Redis** | ${var.redis_node_type} (${var.redis_num_cache_nodes} node) |
| **ALB** | Application Load Balancer with TLS termination |
| **VPC** | ${var.vpc_cidr} with NAT Gateway |
EOT
        }
      },
      {
        type   = "text"
        x      = 12
        y      = 0
        width  = 12
        height = 10
        properties = {
          markdown = <<-EOT
## Ownership & Documentation

| | |
|---|---|
| **Owner** | ${var.owner} |
| **Team** | ${var.team} |
| **Cost Center** | ${var.cost_center} |
| **Public Facing** | ${var.public_facing ? "Yes" : "No"} |
| **Platform Admin** | ${var.platform_admin_email} |

**Documentation:**
- [Project README](https://github.com/liatrio/mcp-context-forge#readme)
- [Infrastructure README](https://github.com/liatrio/mcp-context-forge/blob/main/infrastructure/README.md)
- [IBM Upstream Repo](https://github.com/IBM/mcp-context-forge)

**Quick Links:**
- [CloudWatch Logs](/cloudwatch/home?region=${var.aws_region}#logsV2:log-groups/log-group/$252Faws$252Fecs$252F${local.name})
- [ECS Service](/ecs/v2/clusters/${local.name}-cluster/services/${local.name}/health?region=${var.aws_region})
- [RDS Instance](/rds/home?region=${var.aws_region}#database:id=${local.name}-db)
- [ElastiCache](/elasticache/home?region=${var.aws_region}#/redis-clusters)
EOT
        }
      },

      # =======================================================================
      # ROW 1: Service Health Overview (Alarm Status)
      # =======================================================================
      {
        type   = "alarm"
        x      = 0
        y      = 10
        width  = 24
        height = 5
        properties = {
          title = "Service Health - Alarm Status"
          alarms = [
            aws_cloudwatch_metric_alarm.high_cpu.arn,
            aws_cloudwatch_metric_alarm.high_memory.arn,
            aws_cloudwatch_metric_alarm.unhealthy_hosts.arn,
            aws_cloudwatch_metric_alarm.high_5xx.arn,
            aws_cloudwatch_metric_alarm.high_4xx.arn,
            aws_cloudwatch_metric_alarm.high_latency.arn,
            aws_cloudwatch_metric_alarm.no_healthy_hosts.arn,
            aws_cloudwatch_metric_alarm.rds_high_cpu.arn,
            aws_cloudwatch_metric_alarm.rds_low_storage.arn,
            aws_cloudwatch_metric_alarm.rds_high_connections.arn,
            aws_cloudwatch_metric_alarm.redis_high_cpu.arn,
            aws_cloudwatch_metric_alarm.redis_high_memory.arn,
            aws_cloudwatch_metric_alarm.task_count_low.arn,
            aws_cloudwatch_metric_alarm.log_errors.arn
          ]
        }
      },

      # =======================================================================
      # ROW 2: Container Health & Task Status
      # =======================================================================
      {
        type   = "metric"
        x      = 0
        y      = 15
        width  = 8
        height = 6
        properties = {
          title   = "Container Tasks"
          region  = var.aws_region
          view    = "timeSeries"
          stacked = false
          metrics = [
            ["ECS/ContainerInsights", "RunningTaskCount", "ClusterName", module.ecs_cluster.name, "ServiceName", aws_ecs_service.app.name, { label = "Running Tasks", color = "#2ca02c" }],
            ["ECS/ContainerInsights", "DesiredTaskCount", "ClusterName", module.ecs_cluster.name, "ServiceName", aws_ecs_service.app.name, { label = "Desired Tasks", color = "#1f77b4" }],
            ["ECS/ContainerInsights", "PendingTaskCount", "ClusterName", module.ecs_cluster.name, "ServiceName", aws_ecs_service.app.name, { label = "Pending Tasks", color = "#ff7f0e" }]
          ]
          period = 60
          stat   = "Average"
          annotations = {
            horizontal = [
              { value = var.min_capacity, label = "Min Capacity", color = "#d62728" }
            ]
          }
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 15
        width  = 8
        height = 6
        properties = {
          title   = "Target Health"
          region  = var.aws_region
          view    = "timeSeries"
          stacked = false
          metrics = [
            ["AWS/ApplicationELB", "HealthyHostCount", "LoadBalancer", module.alb.arn_suffix, "TargetGroup", module.alb.target_groups["ecs"].arn_suffix, { label = "Healthy", color = "#2ca02c" }],
            ["AWS/ApplicationELB", "UnHealthyHostCount", "LoadBalancer", module.alb.arn_suffix, "TargetGroup", module.alb.target_groups["ecs"].arn_suffix, { label = "Unhealthy", color = "#d62728" }]
          ]
          period = 60
          stat   = "Average"
        }
      },
      {
        type   = "metric"
        x      = 16
        y      = 15
        width  = 8
        height = 6
        properties = {
          title   = "CPU & Memory Utilization"
          region  = var.aws_region
          view    = "timeSeries"
          stacked = false
          metrics = [
            ["AWS/ECS", "CPUUtilization", "ClusterName", module.ecs_cluster.name, "ServiceName", aws_ecs_service.app.name, { label = "CPU %", color = "#ff7f0e" }],
            ["AWS/ECS", "MemoryUtilization", "ClusterName", module.ecs_cluster.name, "ServiceName", aws_ecs_service.app.name, { label = "Memory %", color = "#9467bd" }]
          ]
          period = 60
          stat   = "Average"
          yAxis = {
            left = { min = 0, max = 100 }
          }
          annotations = {
            horizontal = [
              { value = var.cpu_target_value, label = "Scale Threshold", color = "#d62728" }
            ]
          }
        }
      },

      # =======================================================================
      # ROW 3: Container Insights Detailed Metrics
      # =======================================================================
      {
        type   = "metric"
        x      = 0
        y      = 21
        width  = 8
        height = 6
        properties = {
          title   = "Container CPU Reservation vs Usage"
          region  = var.aws_region
          view    = "timeSeries"
          stacked = false
          metrics = [
            ["ECS/ContainerInsights", "CpuReserved", "ClusterName", module.ecs_cluster.name, "ServiceName", aws_ecs_service.app.name, { label = "CPU Reserved" }],
            ["ECS/ContainerInsights", "CpuUtilized", "ClusterName", module.ecs_cluster.name, "ServiceName", aws_ecs_service.app.name, { label = "CPU Utilized" }]
          ]
          period = 60
          stat   = "Average"
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 21
        width  = 8
        height = 6
        properties = {
          title   = "Container Memory Reservation vs Usage"
          region  = var.aws_region
          view    = "timeSeries"
          stacked = false
          metrics = [
            ["ECS/ContainerInsights", "MemoryReserved", "ClusterName", module.ecs_cluster.name, "ServiceName", aws_ecs_service.app.name, { label = "Memory Reserved (MB)" }],
            ["ECS/ContainerInsights", "MemoryUtilized", "ClusterName", module.ecs_cluster.name, "ServiceName", aws_ecs_service.app.name, { label = "Memory Utilized (MB)" }]
          ]
          period = 60
          stat   = "Average"
        }
      },
      {
        type   = "metric"
        x      = 16
        y      = 21
        width  = 8
        height = 6
        properties = {
          title   = "Container Network I/O"
          region  = var.aws_region
          view    = "timeSeries"
          stacked = false
          metrics = [
            ["ECS/ContainerInsights", "NetworkRxBytes", "ClusterName", module.ecs_cluster.name, "ServiceName", aws_ecs_service.app.name, { label = "Rx Bytes/sec", color = "#2ca02c" }],
            ["ECS/ContainerInsights", "NetworkTxBytes", "ClusterName", module.ecs_cluster.name, "ServiceName", aws_ecs_service.app.name, { label = "Tx Bytes/sec", color = "#1f77b4" }]
          ]
          period = 60
          stat   = "Average"
        }
      },

      # =======================================================================
      # ROW 4: Application Load Balancer Metrics
      # =======================================================================
      {
        type   = "metric"
        x      = 0
        y      = 27
        width  = 8
        height = 6
        properties = {
          title   = "Request Rate & Connections"
          region  = var.aws_region
          view    = "timeSeries"
          stacked = false
          metrics = [
            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", module.alb.arn_suffix, { label = "Requests/min", color = "#1f77b4" }],
            ["AWS/ApplicationELB", "ActiveConnectionCount", "LoadBalancer", module.alb.arn_suffix, { label = "Active Connections", color = "#ff7f0e" }],
            ["AWS/ApplicationELB", "NewConnectionCount", "LoadBalancer", module.alb.arn_suffix, { label = "New Connections", color = "#2ca02c" }]
          ]
          period = 60
          stat   = "Sum"
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 27
        width  = 8
        height = 6
        properties = {
          title   = "Response Latency"
          region  = var.aws_region
          view    = "timeSeries"
          stacked = false
          metrics = [
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", module.alb.arn_suffix, { label = "p50", stat = "p50", color = "#2ca02c" }],
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", module.alb.arn_suffix, { label = "p90", stat = "p90", color = "#ff7f0e" }],
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", module.alb.arn_suffix, { label = "p99", stat = "p99", color = "#d62728" }]
          ]
          period = 60
          annotations = {
            horizontal = [
              { value = 1, label = "1s SLA", color = "#d62728" }
            ]
          }
        }
      },
      {
        type   = "metric"
        x      = 16
        y      = 27
        width  = 8
        height = 6
        properties = {
          title   = "HTTP Response Codes"
          region  = var.aws_region
          view    = "timeSeries"
          stacked = true
          metrics = [
            ["AWS/ApplicationELB", "HTTPCode_Target_2XX_Count", "LoadBalancer", module.alb.arn_suffix, { label = "2xx Success", color = "#2ca02c" }],
            ["AWS/ApplicationELB", "HTTPCode_Target_3XX_Count", "LoadBalancer", module.alb.arn_suffix, { label = "3xx Redirect", color = "#1f77b4" }],
            ["AWS/ApplicationELB", "HTTPCode_Target_4XX_Count", "LoadBalancer", module.alb.arn_suffix, { label = "4xx Client Error", color = "#ff7f0e" }],
            ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", "LoadBalancer", module.alb.arn_suffix, { label = "5xx Server Error", color = "#d62728" }]
          ]
          period = 60
          stat   = "Sum"
        }
      },

      # =======================================================================
      # ROW 5: Error Analysis
      # =======================================================================
      {
        type   = "metric"
        x      = 0
        y      = 33
        width  = 12
        height = 6
        properties = {
          title   = "Error Rate Analysis"
          region  = var.aws_region
          view    = "timeSeries"
          stacked = false
          metrics = [
            ["AWS/ApplicationELB", "HTTPCode_ELB_5XX_Count", "LoadBalancer", module.alb.arn_suffix, { label = "ALB 5xx (infra)", color = "#d62728" }],
            ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", "LoadBalancer", module.alb.arn_suffix, { label = "Target 5xx (app)", color = "#ff7f0e" }],
            ["AWS/ApplicationELB", "TargetConnectionErrorCount", "LoadBalancer", module.alb.arn_suffix, { label = "Connection Errors", color = "#9467bd" }],
            ["AWS/ApplicationELB", "RejectedConnectionCount", "LoadBalancer", module.alb.arn_suffix, { label = "Rejected Connections", color = "#8c564b" }]
          ]
          period = 60
          stat   = "Sum"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 33
        width  = 12
        height = 6
        properties = {
          title   = "Application Logs - Error Count"
          region  = var.aws_region
          view    = "timeSeries"
          stacked = false
          metrics = [
            ["${local.name}", "ErrorCount", { label = "Errors", color = "#d62728" }],
            ["${local.name}", "WarningCount", { label = "Warnings", color = "#ff7f0e" }]
          ]
          period = 60
          stat   = "Sum"
        }
      },

      # =======================================================================
      # ROW 6: Database Metrics
      # =======================================================================
      {
        type   = "metric"
        x      = 0
        y      = 39
        width  = 8
        height = 6
        properties = {
          title   = "RDS Connections & Throughput"
          region  = var.aws_region
          view    = "timeSeries"
          stacked = false
          metrics = [
            ["AWS/RDS", "DatabaseConnections", "DBInstanceIdentifier", module.rds.db_instance_identifier, { label = "Connections", color = "#1f77b4" }],
            ["AWS/RDS", "ReadIOPS", "DBInstanceIdentifier", module.rds.db_instance_identifier, { label = "Read IOPS", color = "#2ca02c" }],
            ["AWS/RDS", "WriteIOPS", "DBInstanceIdentifier", module.rds.db_instance_identifier, { label = "Write IOPS", color = "#ff7f0e" }]
          ]
          period = 60
          stat   = "Average"
          annotations = {
            horizontal = [
              { value = 120, label = "Alarm Threshold (80%)", color = "#ff7f0e" },
              { value = 150, label = "Max Connections", color = "#d62728" }
            ]
          }
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 39
        width  = 8
        height = 6
        properties = {
          title   = "RDS CPU & Memory"
          region  = var.aws_region
          view    = "timeSeries"
          stacked = false
          metrics = [
            ["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", module.rds.db_instance_identifier, { label = "CPU %", color = "#ff7f0e" }],
            ["AWS/RDS", "FreeableMemory", "DBInstanceIdentifier", module.rds.db_instance_identifier, { label = "Free Memory (bytes)", color = "#2ca02c", yAxis = "right" }]
          ]
          period = 60
          stat   = "Average"
          yAxis = {
            left = { min = 0, max = 100 }
          }
        }
      },
      {
        type   = "metric"
        x      = 16
        y      = 39
        width  = 8
        height = 6
        properties = {
          title   = "RDS Storage & Latency"
          region  = var.aws_region
          view    = "timeSeries"
          stacked = false
          metrics = [
            ["AWS/RDS", "FreeStorageSpace", "DBInstanceIdentifier", module.rds.db_instance_identifier, { label = "Free Storage (bytes)", color = "#1f77b4" }],
            ["AWS/RDS", "ReadLatency", "DBInstanceIdentifier", module.rds.db_instance_identifier, { label = "Read Latency", color = "#2ca02c", yAxis = "right" }],
            ["AWS/RDS", "WriteLatency", "DBInstanceIdentifier", module.rds.db_instance_identifier, { label = "Write Latency", color = "#ff7f0e", yAxis = "right" }]
          ]
          period = 60
          stat   = "Average"
        }
      },

      # =======================================================================
      # ROW 7: Redis Cache Metrics
      # =======================================================================
      {
        type   = "metric"
        x      = 0
        y      = 45
        width  = 8
        height = 6
        properties = {
          title   = "Redis Connections & Commands"
          region  = var.aws_region
          view    = "timeSeries"
          stacked = false
          metrics = [
            ["AWS/ElastiCache", "CurrConnections", "CacheClusterId", aws_elasticache_cluster.redis.cluster_id, { label = "Connections", color = "#1f77b4" }],
            ["AWS/ElastiCache", "GetTypeCmds", "CacheClusterId", aws_elasticache_cluster.redis.cluster_id, { label = "GET Commands", color = "#2ca02c" }],
            ["AWS/ElastiCache", "SetTypeCmds", "CacheClusterId", aws_elasticache_cluster.redis.cluster_id, { label = "SET Commands", color = "#ff7f0e" }]
          ]
          period = 60
          stat   = "Average"
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 45
        width  = 8
        height = 6
        properties = {
          title   = "Redis CPU & Memory"
          region  = var.aws_region
          view    = "timeSeries"
          stacked = false
          metrics = [
            ["AWS/ElastiCache", "CPUUtilization", "CacheClusterId", aws_elasticache_cluster.redis.cluster_id, { label = "CPU %", color = "#ff7f0e" }],
            ["AWS/ElastiCache", "DatabaseMemoryUsagePercentage", "CacheClusterId", aws_elasticache_cluster.redis.cluster_id, { label = "Memory %", color = "#9467bd" }]
          ]
          period = 60
          stat   = "Average"
          yAxis = {
            left = { min = 0, max = 100 }
          }
        }
      },
      {
        type   = "metric"
        x      = 16
        y      = 45
        width  = 8
        height = 6
        properties = {
          title   = "Redis Cache Hit Rate"
          region  = var.aws_region
          view    = "timeSeries"
          stacked = false
          metrics = [
            ["AWS/ElastiCache", "CacheHits", "CacheClusterId", aws_elasticache_cluster.redis.cluster_id, { label = "Cache Hits", color = "#2ca02c" }],
            ["AWS/ElastiCache", "CacheMisses", "CacheClusterId", aws_elasticache_cluster.redis.cluster_id, { label = "Cache Misses", color = "#d62728" }]
          ]
          period = 60
          stat   = "Sum"
        }
      },

      # =======================================================================
      # ROW 8: Cost & Usage Metrics
      # =======================================================================
      {
        type   = "metric"
        x      = 0
        y      = 51
        width  = 8
        height = 6
        properties = {
          title   = "Service Cost by Tag (Daily)"
          region  = "us-east-1"
          view    = "timeSeries"
          stacked = true
          metrics = [
            ["AWS/Billing", "EstimatedCharges", "ServiceName", "Amazon Elastic Container Service", "Currency", "USD", { label = "ECS", color = "#1f77b4" }],
            ["AWS/Billing", "EstimatedCharges", "ServiceName", "Amazon Relational Database Service", "Currency", "USD", { label = "RDS", color = "#2ca02c" }],
            ["AWS/Billing", "EstimatedCharges", "ServiceName", "Amazon ElastiCache", "Currency", "USD", { label = "ElastiCache", color = "#ff7f0e" }],
            ["AWS/Billing", "EstimatedCharges", "ServiceName", "Amazon Virtual Private Cloud", "Currency", "USD", { label = "VPC/NAT", color = "#d62728" }],
            ["AWS/Billing", "EstimatedCharges", "ServiceName", "Elastic Load Balancing", "Currency", "USD", { label = "ALB", color = "#9467bd" }]
          ]
          period = 86400
          stat   = "Maximum"
          yAxis = {
            left = { label = "USD", showUnits = false }
          }
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 51
        width  = 8
        height = 6
        properties = {
          title  = "Total Account Charges (MTD)"
          region = "us-east-1"
          view   = "singleValue"
          metrics = [
            ["AWS/Billing", "EstimatedCharges", "Currency", "USD", { label = "Total MTD", color = "#1f77b4" }]
          ]
          period = 21600
          stat   = "Maximum"
        }
      },
      {
        type   = "metric"
        x      = 16
        y      = 51
        width  = 8
        height = 6
        properties = {
          title   = "Data Transfer (Cost Driver)"
          region  = var.aws_region
          view    = "timeSeries"
          stacked = true
          metrics = [
            ["AWS/ApplicationELB", "ProcessedBytes", "LoadBalancer", module.alb.arn_suffix, { label = "ALB Processed Bytes", color = "#2ca02c" }],
            ["AWS/NATGateway", "BytesOutToDestination", "NatGatewayId", module.vpc.natgw_ids[0], { label = "NAT Bytes Out", color = "#ff7f0e" }],
            ["AWS/NATGateway", "BytesInFromDestination", "NatGatewayId", module.vpc.natgw_ids[0], { label = "NAT Bytes In", color = "#1f77b4" }]
          ]
          period = 3600
          stat   = "Sum"
        }
      },

      # =======================================================================
      # ROW 9: Application Logs
      # =======================================================================
      {
        type   = "log"
        x      = 0
        y      = 57
        width  = 12
        height = 6
        properties = {
          title  = "Recent Errors & Warnings"
          region = var.aws_region
          query  = "SOURCE '${aws_cloudwatch_log_group.ecs.name}' | fields @timestamp, @message | filter @message like /(?i)(error|exception|failed|critical|warning)/ | sort @timestamp desc | limit 50"
        }
      },
      {
        type   = "log"
        x      = 12
        y      = 57
        width  = 12
        height = 6
        properties = {
          title  = "All Recent Logs"
          region = var.aws_region
          query  = "SOURCE '${aws_cloudwatch_log_group.ecs.name}' | fields @timestamp, @message | sort @timestamp desc | limit 100"
        }
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# CloudWatch Alarms - ECS / Container Health
# -----------------------------------------------------------------------------

# High CPU Alarm
resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  alarm_name          = "${local.name}-high-cpu"
  alarm_description   = "ECS CPU utilization exceeds 80%"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = 300
  statistic           = "Average"
  threshold           = 80

  dimensions = {
    ClusterName = module.ecs_cluster.name
    ServiceName = aws_ecs_service.app.name
  }

  alarm_actions = var.alarm_sns_topic_arn != "" ? [var.alarm_sns_topic_arn] : []
  ok_actions    = var.alarm_sns_topic_arn != "" ? [var.alarm_sns_topic_arn] : []

  tags = local.tags
}

# High Memory Alarm
resource "aws_cloudwatch_metric_alarm" "high_memory" {
  alarm_name          = "${local.name}-high-memory"
  alarm_description   = "ECS Memory utilization exceeds 80%"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "MemoryUtilization"
  namespace           = "AWS/ECS"
  period              = 300
  statistic           = "Average"
  threshold           = 80

  dimensions = {
    ClusterName = module.ecs_cluster.name
    ServiceName = aws_ecs_service.app.name
  }

  alarm_actions = var.alarm_sns_topic_arn != "" ? [var.alarm_sns_topic_arn] : []
  ok_actions    = var.alarm_sns_topic_arn != "" ? [var.alarm_sns_topic_arn] : []

  tags = local.tags
}

# High Error Rate Alarm
resource "aws_cloudwatch_metric_alarm" "high_5xx" {
  alarm_name          = "${local.name}-high-5xx"
  alarm_description   = "ALB 5XX error count exceeds threshold"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 300
  statistic           = "Sum"
  threshold           = 50

  dimensions = {
    LoadBalancer = module.alb.arn_suffix
  }

  alarm_actions      = var.alarm_sns_topic_arn != "" ? [var.alarm_sns_topic_arn] : []
  ok_actions         = var.alarm_sns_topic_arn != "" ? [var.alarm_sns_topic_arn] : []
  treat_missing_data = "notBreaching"

  tags = local.tags
}

# Unhealthy Target Alarm
resource "aws_cloudwatch_metric_alarm" "unhealthy_hosts" {
  alarm_name          = "${local.name}-unhealthy-hosts"
  alarm_description   = "Unhealthy target count exceeds 0"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Average"
  threshold           = 0

  dimensions = {
    LoadBalancer = module.alb.arn_suffix
    TargetGroup  = module.alb.target_groups["ecs"].arn_suffix
  }

  alarm_actions = var.alarm_sns_topic_arn != "" ? [var.alarm_sns_topic_arn] : []
  ok_actions    = var.alarm_sns_topic_arn != "" ? [var.alarm_sns_topic_arn] : []

  tags = local.tags
}

# RDS High CPU Alarm
resource "aws_cloudwatch_metric_alarm" "rds_high_cpu" {
  alarm_name          = "${local.name}-rds-high-cpu"
  alarm_description   = "RDS CPU utilization exceeds 80%"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 80

  dimensions = {
    DBInstanceIdentifier = module.rds.db_instance_identifier
  }

  alarm_actions = var.alarm_sns_topic_arn != "" ? [var.alarm_sns_topic_arn] : []
  ok_actions    = var.alarm_sns_topic_arn != "" ? [var.alarm_sns_topic_arn] : []

  tags = local.tags
}

# RDS Low Storage Alarm
resource "aws_cloudwatch_metric_alarm" "rds_low_storage" {
  alarm_name          = "${local.name}-rds-low-storage"
  alarm_description   = "RDS free storage below 5GB"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "FreeStorageSpace"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 5368709120 # 5GB in bytes

  dimensions = {
    DBInstanceIdentifier = module.rds.db_instance_identifier
  }

  alarm_actions = var.alarm_sns_topic_arn != "" ? [var.alarm_sns_topic_arn] : []
  ok_actions    = var.alarm_sns_topic_arn != "" ? [var.alarm_sns_topic_arn] : []

  tags = local.tags
}

# RDS High Connection Count Alarm
resource "aws_cloudwatch_metric_alarm" "rds_high_connections" {
  alarm_name          = "${local.name}-rds-high-connections"
  alarm_description   = "RDS database connections approaching limit (>120 of 150 max)"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = 60
  statistic           = "Average"
  threshold           = 120 # Alert at 80% of max_connections (150)

  dimensions = {
    DBInstanceIdentifier = module.rds.db_instance_identifier
  }

  alarm_actions      = var.alarm_sns_topic_arn != "" ? [var.alarm_sns_topic_arn] : []
  ok_actions         = var.alarm_sns_topic_arn != "" ? [var.alarm_sns_topic_arn] : []
  treat_missing_data = "notBreaching"

  tags = local.tags
}

# Redis High CPU Alarm
resource "aws_cloudwatch_metric_alarm" "redis_high_cpu" {
  alarm_name          = "${local.name}-redis-high-cpu"
  alarm_description   = "Redis CPU utilization exceeds 80%"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ElastiCache"
  period              = 300
  statistic           = "Average"
  threshold           = 80

  dimensions = {
    CacheClusterId = aws_elasticache_cluster.redis.cluster_id
  }

  alarm_actions = var.alarm_sns_topic_arn != "" ? [var.alarm_sns_topic_arn] : []
  ok_actions    = var.alarm_sns_topic_arn != "" ? [var.alarm_sns_topic_arn] : []

  tags = local.tags
}

# Redis High Memory Alarm
resource "aws_cloudwatch_metric_alarm" "redis_high_memory" {
  alarm_name          = "${local.name}-redis-high-memory"
  alarm_description   = "Redis memory utilization exceeds 80%"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "DatabaseMemoryUsagePercentage"
  namespace           = "AWS/ElastiCache"
  period              = 300
  statistic           = "Average"
  threshold           = 80

  dimensions = {
    CacheClusterId = aws_elasticache_cluster.redis.cluster_id
  }

  alarm_actions = var.alarm_sns_topic_arn != "" ? [var.alarm_sns_topic_arn] : []
  ok_actions    = var.alarm_sns_topic_arn != "" ? [var.alarm_sns_topic_arn] : []

  tags = local.tags
}

# -----------------------------------------------------------------------------
# CloudWatch Alarms - ALB / Application Health
# -----------------------------------------------------------------------------

# High 4XX Error Rate Alarm
resource "aws_cloudwatch_metric_alarm" "high_4xx" {
  alarm_name          = "${local.name}-high-4xx"
  alarm_description   = "ALB 4XX error count exceeds threshold (client errors)"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "HTTPCode_Target_4XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 300
  statistic           = "Sum"
  threshold           = 100

  dimensions = {
    LoadBalancer = module.alb.arn_suffix
  }

  alarm_actions      = var.alarm_sns_topic_arn != "" ? [var.alarm_sns_topic_arn] : []
  ok_actions         = var.alarm_sns_topic_arn != "" ? [var.alarm_sns_topic_arn] : []
  treat_missing_data = "notBreaching"

  tags = local.tags
}

# High Latency Alarm
resource "aws_cloudwatch_metric_alarm" "high_latency" {
  alarm_name          = "${local.name}-high-latency"
  alarm_description   = "ALB p99 latency exceeds 2 seconds"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "TargetResponseTime"
  namespace           = "AWS/ApplicationELB"
  period              = 300
  extended_statistic  = "p99"
  threshold           = 2

  dimensions = {
    LoadBalancer = module.alb.arn_suffix
  }

  alarm_actions      = var.alarm_sns_topic_arn != "" ? [var.alarm_sns_topic_arn] : []
  ok_actions         = var.alarm_sns_topic_arn != "" ? [var.alarm_sns_topic_arn] : []
  treat_missing_data = "notBreaching"

  tags = local.tags
}

# No Healthy Hosts Alarm (Critical)
resource "aws_cloudwatch_metric_alarm" "no_healthy_hosts" {
  alarm_name          = "${local.name}-no-healthy-hosts"
  alarm_description   = "CRITICAL: No healthy targets in the target group"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "HealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Minimum"
  threshold           = 1

  dimensions = {
    LoadBalancer = module.alb.arn_suffix
    TargetGroup  = module.alb.target_groups["ecs"].arn_suffix
  }

  alarm_actions = var.alarm_sns_topic_arn != "" ? [var.alarm_sns_topic_arn] : []
  ok_actions    = var.alarm_sns_topic_arn != "" ? [var.alarm_sns_topic_arn] : []

  tags = local.tags
}

# -----------------------------------------------------------------------------
# CloudWatch Alarms - ECS Task Health
# -----------------------------------------------------------------------------

# Task Count Low Alarm
resource "aws_cloudwatch_metric_alarm" "task_count_low" {
  alarm_name          = "${local.name}-task-count-low"
  alarm_description   = "Running task count below minimum capacity"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "RunningTaskCount"
  namespace           = "ECS/ContainerInsights"
  period              = 60
  statistic           = "Average"
  threshold           = var.min_capacity

  dimensions = {
    ClusterName = module.ecs_cluster.name
    ServiceName = aws_ecs_service.app.name
  }

  alarm_actions      = var.alarm_sns_topic_arn != "" ? [var.alarm_sns_topic_arn] : []
  ok_actions         = var.alarm_sns_topic_arn != "" ? [var.alarm_sns_topic_arn] : []
  treat_missing_data = "breaching"

  tags = local.tags
}

# -----------------------------------------------------------------------------
# CloudWatch Log Metric Filters
# -----------------------------------------------------------------------------

# Error count metric filter
resource "aws_cloudwatch_log_metric_filter" "error_count" {
  name           = "${local.name}-error-count"
  log_group_name = aws_cloudwatch_log_group.ecs.name
  pattern        = "?ERROR ?error ?Error ?CRITICAL ?critical ?Critical ?Exception ?exception"

  metric_transformation {
    name          = "ErrorCount"
    namespace     = local.name
    value         = "1"
    default_value = "0"
  }
}

# Warning count metric filter
resource "aws_cloudwatch_log_metric_filter" "warning_count" {
  name           = "${local.name}-warning-count"
  log_group_name = aws_cloudwatch_log_group.ecs.name
  pattern        = "?WARNING ?warning ?Warning ?WARN ?warn ?Warn"

  metric_transformation {
    name          = "WarningCount"
    namespace     = local.name
    value         = "1"
    default_value = "0"
  }
}

# Log Errors Alarm
resource "aws_cloudwatch_metric_alarm" "log_errors" {
  alarm_name          = "${local.name}-log-errors"
  alarm_description   = "High error rate detected in application logs"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "ErrorCount"
  namespace           = local.name
  period              = 300
  statistic           = "Sum"
  threshold           = 50

  alarm_actions      = var.alarm_sns_topic_arn != "" ? [var.alarm_sns_topic_arn] : []
  ok_actions         = var.alarm_sns_topic_arn != "" ? [var.alarm_sns_topic_arn] : []
  treat_missing_data = "notBreaching"

  tags = local.tags
}

# -----------------------------------------------------------------------------
# VPC Flow Logs (Optional but recommended)
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "vpc_flow_logs" {
  name              = "/aws/vpc/${local.name}-flow-logs"
  retention_in_days = var.log_retention_days
  kms_key_id        = aws_kms_key.main.arn

  tags = local.tags
}

resource "aws_flow_log" "vpc" {
  vpc_id                   = module.vpc.vpc_id
  traffic_type             = "ALL"
  log_destination_type     = "cloud-watch-logs"
  log_destination          = aws_cloudwatch_log_group.vpc_flow_logs.arn
  iam_role_arn             = aws_iam_role.vpc_flow_logs.arn
  max_aggregation_interval = 60

  tags = local.tags
}

resource "aws_iam_role" "vpc_flow_logs" {
  name = "${local.name}-vpc-flow-logs"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "vpc-flow-logs.amazonaws.com"
        }
      }
    ]
  })

  tags = local.tags
}

resource "aws_iam_role_policy" "vpc_flow_logs" {
  name = "${local.name}-vpc-flow-logs"
  role = aws_iam_role.vpc_flow_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Resource = "${aws_cloudwatch_log_group.vpc_flow_logs.arn}:*"
      }
    ]
  })
}
