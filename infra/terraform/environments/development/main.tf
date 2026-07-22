# =============================================================================
# Development Environment — Claude Code Agent
# =============================================================================

data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  prefix     = var.project_prefix

  common_tags = {
    Project     = local.prefix
    Environment = "development"
    ManagedBy   = "terraform"
  }
}

# -----------------------------------------------------
# Secrets
# -----------------------------------------------------
module "secrets" {
  source = "../../modules/secrets"

  prefix       = local.prefix
  tags         = local.common_tags
  github_token = var.github_token
  jira_token   = var.jira_token
}

# -----------------------------------------------------
# ECR
# -----------------------------------------------------
module "ecr" {
  source = "../../modules/ecr"

  prefix = local.prefix
  tags   = local.common_tags
}

# -----------------------------------------------------
# ECS (S3, Log Group, Cluster, Task Definition)
# -----------------------------------------------------
module "ecs" {
  source = "../../modules/ecs"

  prefix                  = local.prefix
  aws_region              = var.aws_region
  account_id              = local.account_id
  tags                    = local.common_tags
  log_retention_days      = var.log_retention_days
  ecs_cpu                 = var.ecs_cpu
  ecs_memory              = var.ecs_memory
  execution_role_arn      = module.iam.ecs_execution_role_arn
  task_role_arn           = module.iam.ecs_task_role_arn
  ecr_repository_url      = module.ecr.repository_url
  github_token_secret_arn = module.secrets.github_token_arn
  jira_token_secret_arn   = module.secrets.jira_token_arn
  claude_model_id         = var.claude_model_id
  default_repo_url        = var.default_repo_url
  default_base_branch     = var.default_base_branch
  default_test_command    = var.default_test_command
  max_turns               = var.max_turns
}

# -----------------------------------------------------
# IAM
# -----------------------------------------------------
module "iam" {
  source = "../../modules/iam"

  prefix             = local.prefix
  aws_region         = var.aws_region
  tags               = local.common_tags
  ticket_bucket_arn  = module.ecs.ticket_bucket_arn
  log_group_arn      = module.ecs.log_group_arn
  webhook_secret_arn = module.secrets.webhook_secret_arn
}

# -----------------------------------------------------
# Lambda + API Gateway
# -----------------------------------------------------
module "lambda" {
  source = "../../modules/lambda"

  prefix                     = local.prefix
  tags                       = local.common_tags
  lambda_role_arn            = module.iam.lambda_role_arn
  lambda_source_dir          = "${path.module}/../../../../scripts/dispatcher"
  ecs_cluster_name           = module.ecs.cluster_name
  ecs_task_definition_family = module.ecs.task_definition_family
  subnet_ids                 = var.subnet_ids
  security_group_ids         = var.security_group_ids
  ticket_bucket_id           = module.ecs.ticket_bucket_id
}

# -----------------------------------------------------
# Monitoring
# -----------------------------------------------------
module "monitoring" {
  source = "../../modules/monitoring"

  prefix           = local.prefix
  tags             = local.common_tags
  alarm_email      = var.alarm_email
  ecs_cluster_name = module.ecs.cluster_name
}
