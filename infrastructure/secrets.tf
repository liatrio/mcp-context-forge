# -----------------------------------------------------------------------------
# Random Password Generation
# -----------------------------------------------------------------------------

resource "random_password" "jwt_secret" {
  length  = 64
  special = false
}

resource "random_password" "auth_encryption_secret" {
  length  = 64
  special = false
}

resource "random_password" "basic_auth_password" {
  length  = 32
  special = true
}

resource "random_password" "platform_admin_password" {
  length  = 32
  special = true
}

# -----------------------------------------------------------------------------
# Application Secrets
# -----------------------------------------------------------------------------

resource "aws_secretsmanager_secret" "app_secrets" {
  name        = "${local.name}/app-secrets"
  description = "Application secrets for MCP Gateway"
  kms_key_id  = aws_kms_key.main.arn

  tags = local.tags
}

resource "aws_secretsmanager_secret_version" "app_secrets" {
  secret_id = aws_secretsmanager_secret.app_secrets.id

  secret_string = jsonencode({
    JWT_SECRET_KEY          = random_password.jwt_secret.result
    AUTH_ENCRYPTION_SECRET  = random_password.auth_encryption_secret.result
    BASIC_AUTH_USER         = var.basic_auth_user
    BASIC_AUTH_PASSWORD     = random_password.basic_auth_password.result
    PLATFORM_ADMIN_EMAIL    = var.platform_admin_email
    PLATFORM_ADMIN_PASSWORD = random_password.platform_admin_password.result
  })

  lifecycle {
    ignore_changes = [secret_string]
  }
}

# -----------------------------------------------------------------------------
# Database URL Secret
# Constructed from RDS module outputs with password from RDS-managed secret
# -----------------------------------------------------------------------------

# Fetch the RDS-managed master password secret
data "aws_secretsmanager_secret_version" "rds_master_password" {
  secret_id = module.rds.db_instance_master_user_secret_arn
}

locals {
  # Parse the RDS password from the managed secret
  rds_credentials = jsondecode(data.aws_secretsmanager_secret_version.rds_master_password.secret_string)
  db_password     = local.rds_credentials["password"]

  # Construct the full DATABASE_URL with password (URL-encoded for special chars)
  database_url = "postgresql://${var.db_username}:${urlencode(local.db_password)}@${module.rds.db_instance_endpoint}/${var.db_name}?sslmode=require"
}

resource "aws_secretsmanager_secret" "database_url" {
  name        = "${local.name}/database-url"
  description = "Database connection URL for MCP Gateway"
  kms_key_id  = aws_kms_key.main.arn

  tags = local.tags
}

resource "aws_secretsmanager_secret_version" "database_url" {
  secret_id     = aws_secretsmanager_secret.database_url.id
  secret_string = local.database_url
}

# -----------------------------------------------------------------------------
# SSO Secrets (Optional)
# -----------------------------------------------------------------------------

resource "aws_secretsmanager_secret" "sso_secrets" {
  count = var.sso_enabled ? 1 : 0

  name        = "${local.name}/sso-secrets"
  description = "SSO configuration secrets for MCP Gateway"
  kms_key_id  = aws_kms_key.main.arn

  tags = local.tags
}

resource "aws_secretsmanager_secret_version" "sso_secrets" {
  count = var.sso_enabled ? 1 : 0

  secret_id = aws_secretsmanager_secret.sso_secrets[0].id

  secret_string = jsonencode({
    # General SSO settings
    SSO_ENABLED             = tostring(var.sso_enabled)
    SSO_AUTO_CREATE_USERS   = tostring(var.sso_auto_create_users)
    SSO_PRESERVE_ADMIN_AUTH = tostring(var.sso_preserve_admin_auth)
    SSO_TRUSTED_DOMAINS     = jsonencode(var.sso_trusted_domains)

    # GitHub OAuth
    SSO_GITHUB_ENABLED       = tostring(var.sso_github_enabled)
    SSO_GITHUB_CLIENT_ID     = var.sso_github_client_id
    SSO_GITHUB_CLIENT_SECRET = var.sso_github_client_secret
    SSO_GITHUB_ADMIN_ORGS    = jsonencode(var.sso_github_admin_orgs)
    SSO_GITHUB_SCOPE         = var.sso_github_scope

    # Microsoft Entra ID
    SSO_ENTRA_ENABLED       = tostring(var.sso_entra_enabled)
    SSO_ENTRA_CLIENT_ID     = var.sso_entra_client_id
    SSO_ENTRA_CLIENT_SECRET = var.sso_entra_client_secret
    SSO_ENTRA_TENANT_ID     = var.sso_entra_tenant_id
  })

  lifecycle {
    ignore_changes = [secret_string]
  }
}

