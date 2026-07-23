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
  description = "AWS region for dashboard widgets"
  type        = string
}

variable "alarm_email" {
  description = "Email for alarm notifications (optional)"
  type        = string
  default     = ""
}

variable "ecs_cluster_name" {
  description = "ECS cluster name for alarm dimensions"
  type        = string
}

variable "ecs_log_group_name" {
  description = "CloudWatch log group name for ECS agent tasks"
  type        = string
}

variable "lambda_function_name" {
  description = "Lambda dispatcher function name for alarm dimensions"
  type        = string
}

variable "lambda_log_group_name" {
  description = "CloudWatch log group name for dispatcher Lambda"
  type        = string
}

variable "sns_topic_arn" {
  description = "SNS topic ARN for budget alarm actions (self-referencing for bootstrap)"
  type        = string
  default     = ""
}
