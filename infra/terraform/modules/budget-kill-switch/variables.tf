variable "prefix" {
  description = "Resource naming prefix"
  type        = string
}

variable "tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default     = {}
}

variable "aws_region" {
  description = "AWS region for ECS"
  type        = string
}

variable "bedrock_region" {
  description = "AWS region for Bedrock inference"
  type        = string
  default     = "eu-central-1"
}

variable "ecs_cluster_name" {
  description = "ECS cluster name"
  type        = string
}

variable "ecs_task_role_name" {
  description = "Name of the ECS task role (for revoking Bedrock access)"
  type        = string
}

variable "sns_topic_arn" {
  description = "SNS topic ARN for notifications"
  type        = string
}

variable "daily_token_limit" {
  description = "Max daily Bedrock token usage before kill switch triggers"
  type        = number
  default     = 5000000
}

variable "daily_cost_limit" {
  description = "Max daily Bedrock cost (USD) before kill switch triggers"
  type        = number
  default     = 50
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 30
}

variable "lambda_source_dir" {
  description = "Path to kill switch Lambda source"
  type        = string
  default     = ""
}
