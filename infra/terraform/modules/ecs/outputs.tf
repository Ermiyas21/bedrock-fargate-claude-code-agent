output "cluster_name" {
  description = "ECS cluster name"
  value       = aws_ecs_cluster.agent.name
}

output "task_definition_family" {
  description = "ECS task definition family"
  value       = aws_ecs_task_definition.agent.family
}

output "ticket_bucket_id" {
  description = "S3 ticket bucket ID"
  value       = aws_s3_bucket.tickets.id
}

output "ticket_bucket_arn" {
  description = "S3 ticket bucket ARN"
  value       = aws_s3_bucket.tickets.arn
}

output "log_group_name" {
  description = "CloudWatch log group name"
  value       = aws_cloudwatch_log_group.ecs.name
}

output "log_group_arn" {
  description = "CloudWatch log group ARN"
  value       = aws_cloudwatch_log_group.ecs.arn
}
