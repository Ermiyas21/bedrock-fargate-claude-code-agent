# =============================================================================
# S3 Bucket (tickets), CloudWatch Log Group, ECS Cluster, Task Definition
# =============================================================================

# -----------------------------------------------------
# S3 Bucket for ticket storage
# -----------------------------------------------------
resource "aws_s3_bucket" "tickets" {
  bucket = "${var.prefix}-tickets-${var.account_id}"
  tags   = var.tags
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tickets" {
  bucket = aws_s3_bucket.tickets.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tickets" {
  bucket = aws_s3_bucket.tickets.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# -----------------------------------------------------
# CloudWatch Log Group
# -----------------------------------------------------
resource "aws_cloudwatch_log_group" "ecs" {
  name              = "/ecs/${var.prefix}"
  retention_in_days = var.log_retention_days
  tags              = var.tags
}

# -----------------------------------------------------
# ECS Cluster
# -----------------------------------------------------
resource "aws_ecs_cluster" "agent" {
  name = "${var.prefix}-cluster"

  configuration {
    execute_command_configuration {
      logging = "OVERRIDE"

      log_configuration {
        cloud_watch_log_group_name = aws_cloudwatch_log_group.ecs.name
      }
    }
  }

  tags = var.tags
}

resource "aws_ecs_cluster_capacity_providers" "agent" {
  cluster_name = aws_ecs_cluster.agent.name

  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    capacity_provider = "FARGATE_SPOT"
    weight            = 1
    base              = 0
  }
}

# -----------------------------------------------------
# ECS Task Definition
# -----------------------------------------------------
resource "aws_ecs_task_definition" "agent" {
  family                   = "${var.prefix}-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.ecs_cpu
  memory                   = var.ecs_memory
  execution_role_arn       = var.execution_role_arn
  task_role_arn            = var.task_role_arn

  container_definitions = jsonencode([
    {
      name      = "claude-code-agent"
      image     = "${var.ecr_repository_url}:latest"
      essential = true

      environment = [
        { name = "CLAUDE_CODE_USE_BEDROCK", value = "1" },
        { name = "CLAUDE_MODEL_ID", value = var.claude_model_id },
        { name = "AWS_REGION", value = var.bedrock_region },
        { name = "AWS_DEFAULT_REGION", value = var.aws_region },
        { name = "REPO_URL", value = var.default_repo_url },
        { name = "BASE_BRANCH", value = var.default_base_branch },
        { name = "TEST_COMMAND", value = var.default_test_command },
        { name = "MAX_TURNS", value = tostring(var.max_turns) },
      ]

      secrets = concat(
        [
          {
            name      = "GIT_CREDENTIALS_SECRET_ID"
            valueFrom = var.github_token_secret_arn
          }
        ],
        var.jira_token_secret_arn != "" ? [
          {
            name      = "JIRA_TOKEN_SECRET_ID"
            valueFrom = var.jira_token_secret_arn
          }
        ] : [],
        var.linear_token_secret_arn != "" ? [
          {
            name      = "LINEAR_TOKEN_SECRET_ID"
            valueFrom = var.linear_token_secret_arn
          }
        ] : [],
        var.anthropic_api_key_secret_arn != "" ? [
          {
            name      = "ANTHROPIC_API_KEY"
            valueFrom = var.anthropic_api_key_secret_arn
          }
        ] : []
      )

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "agent"
        }
      }

      stopTimeout = 30
    }
  ])

  tags = var.tags
}
