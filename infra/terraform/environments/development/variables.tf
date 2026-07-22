# -----------------------------------------------------
# General
# -----------------------------------------------------
variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "eu-west-2"
}

variable "project_prefix" {
  description = "Prefix used for naming all resources"
  type        = string
  default     = "claude-code-agent"
}

# -----------------------------------------------------
# Secrets (sensitive)
# -----------------------------------------------------
variable "github_token" {
  description = "GitHub Personal Access Token (PAT) with repo scope"
  type        = string
  sensitive   = true
}

variable "jira_token" {
  description = "Jira/Linear API token (optional)"
  type        = string
  sensitive   = true
  default     = ""
}

# -----------------------------------------------------
# Networking
# -----------------------------------------------------
variable "subnet_ids" {
  description = "List of subnet IDs for ECS tasks (public subnets with internet access)"
  type        = list(string)
}

variable "security_group_ids" {
  description = "List of security group IDs for ECS tasks"
  type        = list(string)
}

variable "assign_public_ip" {
  description = "Assign public IP to ECS tasks (required for public subnets without NAT)"
  type        = bool
  default     = true
}

# -----------------------------------------------------
# ECS Task Configuration
# -----------------------------------------------------
variable "ecs_cpu" {
  description = "CPU units for ECS task (1024 = 1 vCPU)"
  type        = number
  default     = 4096
}

variable "ecs_memory" {
  description = "Memory (MiB) for ECS task"
  type        = number
  default     = 16384
}

variable "task_timeout_seconds" {
  description = "Max duration for ECS task in seconds"
  type        = number
  default     = 1800
}

# -----------------------------------------------------
# Claude Code Configuration
# -----------------------------------------------------
variable "claude_model_id" {
  description = "Bedrock model ID for Claude"
  type        = string
  default     = "eu.anthropic.claude-sonnet-4-6"
}

variable "default_repo_url" {
  description = "Default repository URL for the agent"
  type        = string
  default     = "https://github.com/org/repo.git"
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

# -----------------------------------------------------
# Monitoring
# -----------------------------------------------------
variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 30
}

variable "alarm_email" {
  description = "Email for CloudWatch alarm notifications (optional)"
  type        = string
  default     = ""
}
