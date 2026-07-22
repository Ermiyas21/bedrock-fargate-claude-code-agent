output "github_token_arn" {
  description = "ARN of the GitHub token secret"
  value       = aws_secretsmanager_secret.github_token.arn
}

output "webhook_secret_arn" {
  description = "ARN of the webhook secret"
  value       = aws_secretsmanager_secret.webhook_secret.arn
}

output "webhook_secret_value" {
  description = "Webhook secret value for Linear configuration"
  value       = random_password.webhook_secret.result
  sensitive   = true
}
