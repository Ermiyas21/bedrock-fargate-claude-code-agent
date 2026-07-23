# =============================================================================
# Secrets Manager — GitHub token, Jira token, Linear token, Anthropic API key, Webhook secret
# =============================================================================

# GitHub Personal Access Token
resource "aws_secretsmanager_secret" "github_token" {
  name        = "${var.prefix}/github-token"
  description = "GitHub token for Claude Code agent"
  tags        = var.tags
}

resource "aws_secretsmanager_secret_version" "github_token" {
  secret_id     = aws_secretsmanager_secret.github_token.id
  secret_string = var.github_token
}

# Jira API Token (optional)
resource "aws_secretsmanager_secret" "jira_token" {
  count       = var.jira_token != "" ? 1 : 0
  name        = "${var.prefix}/jira-token"
  description = "Jira API token for Claude Code agent"
  tags        = var.tags
}

resource "aws_secretsmanager_secret_version" "jira_token" {
  count         = var.jira_token != "" ? 1 : 0
  secret_id     = aws_secretsmanager_secret.jira_token[0].id
  secret_string = var.jira_token
}

# Linear API Token (optional)
resource "aws_secretsmanager_secret" "linear_token" {
  count       = var.linear_token != "" ? 1 : 0
  name        = "${var.prefix}/linear-token"
  description = "Linear API token for Claude Code agent"
  tags        = var.tags
}

resource "aws_secretsmanager_secret_version" "linear_token" {
  count         = var.linear_token != "" ? 1 : 0
  secret_id     = aws_secretsmanager_secret.linear_token[0].id
  secret_string = var.linear_token
}

# Anthropic API Key — long-term Claude Code token (optional, fallback for non-Bedrock)
resource "aws_secretsmanager_secret" "anthropic_api_key" {
  count       = var.anthropic_api_key != "" ? 1 : 0
  name        = "${var.prefix}/anthropic-api-key"
  description = "Anthropic API key for Claude Code (fallback when not using Bedrock)"
  tags        = var.tags
}

resource "aws_secretsmanager_secret_version" "anthropic_api_key" {
  count         = var.anthropic_api_key != "" ? 1 : 0
  secret_id     = aws_secretsmanager_secret.anthropic_api_key[0].id
  secret_string = var.anthropic_api_key
}

# Webhook secret for Linear/Jira signature verification
resource "random_password" "webhook_secret" {
  length  = 64
  special = false
}

resource "aws_secretsmanager_secret" "webhook_secret" {
  name        = "${var.prefix}/webhook-secret"
  description = "Webhook signature verification secret"
  tags        = var.tags
}

resource "aws_secretsmanager_secret_version" "webhook_secret" {
  secret_id     = aws_secretsmanager_secret.webhook_secret.id
  secret_string = random_password.webhook_secret.result
}
