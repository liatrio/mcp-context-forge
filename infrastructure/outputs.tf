# -----------------------------------------------------------------------------
# Application Outputs
# -----------------------------------------------------------------------------

output "app_url" {
  description = "URL to access the MCP Gateway"
  value       = "https://${var.domain_name}"
}

output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = module.alb.dns_name
}

# -----------------------------------------------------------------------------
# VPC Outputs
# -----------------------------------------------------------------------------

output "vpc_id" {
  description = "ID of the VPC"
  value       = module.vpc.vpc_id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = module.vpc.private_subnets
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = module.vpc.public_subnets
}

# -----------------------------------------------------------------------------
# ECS Outputs
# -----------------------------------------------------------------------------

output "ecs_cluster_name" {
  description = "Name of the ECS cluster"
  value       = module.ecs_cluster.name
}

output "ecs_cluster_arn" {
  description = "ARN of the ECS cluster"
  value       = module.ecs_cluster.arn
}

output "ecs_service_name" {
  description = "Name of the ECS service"
  value       = aws_ecs_service.app.name
}

# -----------------------------------------------------------------------------
# Database Outputs
# -----------------------------------------------------------------------------

output "rds_endpoint" {
  description = "Endpoint of the RDS instance"
  value       = module.rds.db_instance_endpoint
}

output "rds_instance_id" {
  description = "Identifier of the RDS instance"
  value       = module.rds.db_instance_identifier
}

output "rds_master_secret_arn" {
  description = "ARN of the RDS master user secret in Secrets Manager"
  value       = module.rds.db_instance_master_user_secret_arn
  sensitive   = true
}

# -----------------------------------------------------------------------------
# ElastiCache Outputs
# -----------------------------------------------------------------------------

output "redis_endpoint" {
  description = "Endpoint of the Redis cluster"
  value       = aws_elasticache_cluster.redis.cache_nodes[0].address
}

output "redis_port" {
  description = "Port of the Redis cluster"
  value       = aws_elasticache_cluster.redis.port
}

# -----------------------------------------------------------------------------
# Security Outputs
# -----------------------------------------------------------------------------

output "kms_key_arn" {
  description = "ARN of the KMS key used for encryption"
  value       = aws_kms_key.main.arn
}

output "app_secrets_arn" {
  description = "ARN of the application secrets in Secrets Manager"
  value       = aws_secretsmanager_secret.app_secrets.arn
  sensitive   = true
}

# -----------------------------------------------------------------------------
# Monitoring Outputs
# -----------------------------------------------------------------------------

output "cloudwatch_log_group" {
  description = "Name of the CloudWatch log group for ECS"
  value       = aws_cloudwatch_log_group.ecs.name
}

output "cloudwatch_dashboard_url" {
  description = "URL to the CloudWatch dashboard"
  value       = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${local.name}"
}

# -----------------------------------------------------------------------------
# Useful Commands
# -----------------------------------------------------------------------------

output "useful_commands" {
  description = "Helpful AWS CLI commands for managing the deployment"
  value       = <<-EOT
    # View running tasks
    aws ecs list-tasks --cluster ${module.ecs_cluster.name} --service-name ${aws_ecs_service.app.name}

    # Force new deployment (rolling update)
    aws ecs update-service --cluster ${module.ecs_cluster.name} --service-name ${aws_ecs_service.app.name} --force-new-deployment

    # View logs
    aws logs tail ${aws_cloudwatch_log_group.ecs.name} --follow

    # Scale manually
    aws ecs update-service --cluster ${module.ecs_cluster.name} --service-name ${aws_ecs_service.app.name} --desired-count 4

    # Execute command in running container (for debugging)
    aws ecs execute-command --cluster ${module.ecs_cluster.name} --task <task-id> --container mcp-gateway --interactive --command "/bin/sh"
  EOT
}

# -----------------------------------------------------------------------------
# Terraform State Outputs
# -----------------------------------------------------------------------------

output "terraform_state_bucket" {
  description = "S3 bucket for Terraform state storage"
  value       = aws_s3_bucket.terraform_state.id
}

output "terraform_state_bucket_arn" {
  description = "ARN of the S3 bucket for Terraform state"
  value       = aws_s3_bucket.terraform_state.arn
}

output "terraform_backend_config" {
  description = "Configuration for Terraform S3 backend (add to versions.tf)"
  value       = <<-EOT
    # Add this backend configuration to versions.tf after initial apply:
    backend "s3" {
      bucket       = "${aws_s3_bucket.terraform_state.id}"
      key          = "mcp-gateway/terraform.tfstate"
      region       = "${var.aws_region}"
      encrypt      = true
      kms_key_id   = "${aws_kms_key.main.arn}"
      use_lockfile = true
    }
  EOT
}
