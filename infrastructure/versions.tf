terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # S3 backend with native S3 locking (Terraform 1.10+)
  backend "s3" {
    bucket       = "mcp-gateway-dev-terraform-state"
    key          = "mcp-gateway/terraform.tfstate"
    region       = "us-east-2"
    encrypt      = true
    kms_key_id   = "arn:aws:kms:us-east-2:008971644846:key/8094f386-325c-4a29-92df-08fd1ee7bd29"
    use_lockfile = true
  }
}

provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile

  default_tags {
    tags = merge(
      {
        # Project identification
        Project     = "ContextForge-MCP-Gateway"
        Application = var.project_name
        Environment = var.environment

        # Ownership and responsibility
        Owner      = var.owner
        Team       = var.team
        CostCenter = var.cost_center

        # Deployment metadata
        DeploymentDate     = "2025-12-17"
        ManagedBy          = "terraform"
        TerraformWorkspace = terraform.workspace

        # Classification and access
        DataClassification = var.data_classification
        Audience           = "Liatrio Internal"
        PublicFacing       = tostring(var.public_facing)

        # Operational tags
        AutoShutdown  = "false"
        BackupEnabled = "true"

        # Compliance and governance
        Compliance = "internal-policy"
      },
      var.additional_tags
    )
  }
}
