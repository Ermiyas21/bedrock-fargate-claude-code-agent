variable "prefix" {
  description = "Resource naming prefix"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "account_id" {
  description = "AWS account ID"
  type        = string
}

variable "tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default     = {}
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 30
}

variable "ecs_cpu" {
  description = "CPU units for ECS task"
  type        = number
  default     = 4096
}

variable "ecs_memory" {
  description = "Memory (MiB) for ECS task"
  type        = number
  default     = 16384
}

variable "execution_role_arn" {
  description = "ARN of the ECS execution role"
  type        = string
}

variable "task_role_arn" {
  description = "ARN of the ECS task role"
  type        = string
}

variable "ecr_repository_url" {
  description = "ECR repository URL"
  type        = string
}

variable "github_token_secret_arn" {
  description = "ARN of the GitHub token secret"
  type        = string
}

variable "jira_token_secret_arn" {
  description = "ARN of the Jira token secret (empty if not configured)"
  type        = string
  default     = ""
}

variable "claude_model_id" {
  description = "Bedrock model ID"
  type        = string
  default     = "eu.anthropic.claude-sonnet-4-6"
}

variable "default_repo_url" {
  description = "Default repository URL"
  type        = string
}

variable "default_base_branch" {
  description = "Default base branch"
  type        = string
  default     = "main"
}

variable "default_test_command" {
  description = "Default test command"
  type        = string
  default     = "npm test"
}

variable "max_turns" {
  description = "Max Claude Code iterations"
  type        = number
  default     = 50
}
