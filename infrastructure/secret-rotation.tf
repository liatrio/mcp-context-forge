# -----------------------------------------------------------------------------
# Secret Rotation Automation
# Automatically updates ECS service when RDS password rotates
# -----------------------------------------------------------------------------

# Lambda function to force ECS service update
resource "aws_lambda_function" "secret_rotation_handler" {
  function_name = "${local.name}-secret-rotation-handler"
  description   = "Forces ECS service deployment when RDS password rotates"
  runtime       = "python3.12"
  handler       = "index.handler"
  role          = aws_iam_role.secret_rotation_lambda.arn
  timeout       = 60

  # Inline code for simple Lambda
  filename         = data.archive_file.secret_rotation_lambda.output_path
  source_code_hash = data.archive_file.secret_rotation_lambda.output_base64sha256

  environment {
    variables = {
      ECS_CLUSTER         = module.ecs_cluster.name
      ECS_SERVICE         = aws_ecs_service.app.name
      DATABASE_URL_SECRET = aws_secretsmanager_secret.database_url.arn
      RDS_SECRET_ARN      = module.rds.db_instance_master_user_secret_arn
      DB_USERNAME         = var.db_username
      DB_ENDPOINT         = module.rds.db_instance_endpoint
      DB_NAME             = var.db_name
    }
  }

  tags = local.tags
}

# Lambda code archive
data "archive_file" "secret_rotation_lambda" {
  type        = "zip"
  output_path = "${path.module}/.terraform/secret_rotation_lambda.zip"

  source {
    content  = <<-EOF
import boto3
import json
import logging
import os
import urllib.parse

logger = logging.getLogger()
logger.setLevel(logging.INFO)

ecs_client = boto3.client('ecs')
secrets_client = boto3.client('secretsmanager')

def handler(event, context):
    """
    Handles secret rotation events by:
    1. Updating the DATABASE_URL secret with the new password
    2. Forcing a new ECS deployment to pick up the new credentials
    """
    logger.info(f"Received event: {json.dumps(event)}")

    cluster = os.environ['ECS_CLUSTER']
    service = os.environ['ECS_SERVICE']
    db_url_secret_arn = os.environ['DATABASE_URL_SECRET']
    rds_secret_arn = os.environ['RDS_SECRET_ARN']
    db_username = os.environ['DB_USERNAME']
    db_endpoint = os.environ['DB_ENDPOINT']
    db_name = os.environ['DB_NAME']

    try:
        # Get the new RDS password from the rotated secret
        logger.info(f"Fetching new password from RDS secret")
        rds_secret = secrets_client.get_secret_value(SecretId=rds_secret_arn)
        rds_creds = json.loads(rds_secret['SecretString'])
        new_password = rds_creds['password']

        # URL-encode the password for special characters
        encoded_password = urllib.parse.quote(new_password, safe='')

        # Construct the new DATABASE_URL
        new_db_url = f"postgresql://{db_username}:{encoded_password}@{db_endpoint}/{db_name}?sslmode=require"

        # Update the DATABASE_URL secret
        logger.info(f"Updating DATABASE_URL secret")
        secrets_client.put_secret_value(
            SecretId=db_url_secret_arn,
            SecretString=new_db_url
        )
        logger.info("DATABASE_URL secret updated successfully")

        # Force new ECS deployment
        logger.info(f"Forcing new deployment for {service} in {cluster}")
        response = ecs_client.update_service(
            cluster=cluster,
            service=service,
            forceNewDeployment=True
        )

        deployment_id = response['service']['deployments'][0]['id']
        logger.info(f"New deployment started: {deployment_id}")

        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Secret rotated and ECS service updated',
                'deployment_id': deployment_id
            })
        }

    except Exception as e:
        logger.error(f"Error handling secret rotation: {str(e)}")
        raise
EOF
    filename = "index.py"
  }
}

# IAM role for Lambda
resource "aws_iam_role" "secret_rotation_lambda" {
  name = "${local.name}-secret-rotation-lambda"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = local.tags
}

# Lambda basic execution role
resource "aws_iam_role_policy_attachment" "secret_rotation_lambda_basic" {
  role       = aws_iam_role.secret_rotation_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Custom policy for ECS and Secrets Manager access
resource "aws_iam_role_policy" "secret_rotation_lambda" {
  name = "${local.name}-secret-rotation-policy"
  role = aws_iam_role.secret_rotation_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecs:UpdateService",
          "ecs:DescribeServices"
        ]
        Resource = aws_ecs_service.app.id
      },
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = module.rds.db_instance_master_user_secret_arn
      },
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:PutSecretValue"
        ]
        Resource = aws_secretsmanager_secret.database_url.arn
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = [
          aws_kms_key.main.arn
        ]
      }
    ]
  })
}

# EventBridge rule to capture RDS secret rotation events
resource "aws_cloudwatch_event_rule" "secret_rotation" {
  name        = "${local.name}-secret-rotation"
  description = "Captures RDS password rotation events"

  event_pattern = jsonencode({
    source      = ["aws.secretsmanager"]
    detail-type = ["AWS API Call via CloudTrail"]
    detail = {
      eventSource = ["secretsmanager.amazonaws.com"]
      eventName   = ["RotateSecret", "PutSecretValue"]
      requestParameters = {
        secretId = [module.rds.db_instance_master_user_secret_arn]
      }
    }
  })

  tags = local.tags
}

# EventBridge target to invoke Lambda
resource "aws_cloudwatch_event_target" "secret_rotation" {
  rule      = aws_cloudwatch_event_rule.secret_rotation.name
  target_id = "secret-rotation-handler"
  arn       = aws_lambda_function.secret_rotation_handler.arn
}

# Lambda permission for EventBridge
resource "aws_lambda_permission" "secret_rotation" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.secret_rotation_handler.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.secret_rotation.arn
}

# CloudWatch log group for Lambda
resource "aws_cloudwatch_log_group" "secret_rotation_lambda" {
  name              = "/aws/lambda/${local.name}-secret-rotation-handler"
  retention_in_days = var.log_retention_days
  kms_key_id        = aws_kms_key.main.arn

  tags = local.tags
}
