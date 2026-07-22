# =============================================================================
# Secrets Manager — GitHub token, Jira token, Webhook secret
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

# Jira/Linear API Token (optional)
resource "aws_secretsmanager_secret" "jira_token" {
  count       = var.jira_token != "" ? 1 : 0
  name        = "${var.prefix}/jira-token"
  description = "Jira/Linear token for Claude Code agent"
  tags        = var.tags
}

resource "aws_secretsmanager_secret_version" "jira_token" {
  count         = var.jira_token != "" ? 1 : 0
  secret_id     = aws_secretsmanager_secret.jira_token[0].id
  secret_string = var.jira_token
}

# Webhook secret for Linear signature verification
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
