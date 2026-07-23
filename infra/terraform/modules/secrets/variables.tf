variable "prefix" {
  description = "Resource naming prefix"
  type        = string
}

variable "tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default     = {}
}

variable "github_token" {
  description = "GitHub Personal Access Token"
  type        = string
  sensitive   = true
}

variable "jira_token" {
  description = "Jira API token (optional)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "linear_token" {
  description = "Linear API token (optional)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "anthropic_api_key" {
  description = "Anthropic API key for Claude Code (optional — fallback when not using Bedrock)"
  type        = string
  sensitive   = true
  default     = ""
}
