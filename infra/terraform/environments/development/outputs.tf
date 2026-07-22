# =============================================================================
# Outputs
# =============================================================================

output "webhook_url" {
  description = "API Gateway webhook URL — configure this in Linear webhook settings"
  value       = module.lambda.webhook_url
}

output "ecr_repository_url" {
  description = "ECR repository URL for Docker push"
  value       = module.ecr.repository_url
}

output "ecs_cluster_name" {
  description = "ECS cluster name"
  value       = module.ecs.cluster_name
}

output "ecs_task_definition" {
  description = "ECS task definition family"
  value       = module.ecs.task_definition_family
}

output "s3_ticket_bucket" {
  description = "S3 bucket for ticket storage"
  value       = module.ecs.ticket_bucket_id
}

output "lambda_function_name" {
  description = "Lambda dispatcher function name"
  value       = module.lambda.function_name
}

output "cloudwatch_log_group" {
  description = "CloudWatch log group for ECS tasks"
  value       = module.ecs.log_group_name
}

output "sns_topic_arn" {
  description = "SNS topic ARN for alert notifications"
  value       = module.monitoring.sns_topic_arn
}

output "webhook_secret" {
  description = "Webhook secret for Linear signature verification"
  value       = module.secrets.webhook_secret_value
  sensitive   = true
}

# Docker build & push commands
output "docker_push_commands" {
  description = "Commands to build and push Docker image to ECR"
  value       = <<-EOT
    # Authenticate Docker
    aws ecr get-login-password --region ${var.aws_region} | docker login --username AWS --password-stdin ${module.ecr.repository_url}

    # Build (from project root)
    docker build --platform linux/amd64 -t ${local.prefix}:latest docker/

    # Tag and push
    docker tag ${local.prefix}:latest ${module.ecr.repository_url}:latest
    docker push ${module.ecr.repository_url}:latest
  EOT
}

# Manual test command
output "manual_test_command" {
  description = "Command to manually test an ECS task"
  value       = <<-EOT
    python scripts/run-task-manual.py \
      --repo ${var.default_repo_url} \
      --task-id TEST-001 \
      --ticket-body "Add a health check endpoint" \
      --subnets "${join(",", var.subnet_ids)}" \
      --security-groups "${join(",", var.security_group_ids)}" \
      --wait
  EOT
}
