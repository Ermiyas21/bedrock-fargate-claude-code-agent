output "github_token_arn" {
  description = "ARN of the GitHub token secret"
  value       = aws_secretsmanager_secret.github_token.arn
}

output "jira_token_arn" {
  description = "ARN of the Jira token secret (empty if not configured)"
  value       = var.jira_token != "" ? aws_secretsmanager_secret.jira_token[0].arn : ""
}

output "linear_token_arn" {
  description = "ARN of the Linear token secret (empty if not configured)"
  value       = var.linear_token != "" ? aws_secretsmanager_secret.linear_token[0].arn : ""
}

output "anthropic_api_key_arn" {
  description = "ARN of the Anthropic API key secret (empty if not configured)"
  value       = var.anthropic_api_key != "" ? aws_secretsmanager_secret.anthropic_api_key[0].arn : ""
}

output "webhook_secret_arn" {
  description = "ARN of the webhook secret"
  value       = aws_secretsmanager_secret.webhook_secret.arn
}

output "webhook_secret_value" {
  description = "Webhook secret value for Linear/Jira configuration"
  value       = random_password.webhook_secret.result
  sensitive   = true
}

