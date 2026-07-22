variable "prefix" {
  description = "Resource naming prefix"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default     = {}
}

variable "ticket_bucket_arn" {
  description = "ARN of the S3 ticket bucket"
  type        = string
}

variable "log_group_arn" {
  description = "ARN of the CloudWatch log group"
  type        = string
}

variable "webhook_secret_arn" {
  description = "ARN of the webhook secret in Secrets Manager"
  type        = string
}
