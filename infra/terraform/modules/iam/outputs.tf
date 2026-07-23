output "ecs_execution_role_arn" {
  description = "ARN of the ECS execution role"
  value       = aws_iam_role.ecs_execution.arn
}

output "ecs_task_role_arn" {
  description = "ARN of the ECS task role"
  value       = aws_iam_role.ecs_task.arn
}

output "ecs_task_role_name" {
  description = "Name of the ECS task role"
  value       = aws_iam_role.ecs_task.name
}

output "lambda_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.lambda.arn
}

output "lambda_basic_policy_attachment" {
  description = "Lambda basic policy attachment (for depends_on)"
  value       = aws_iam_role_policy_attachment.lambda_basic.id
}

output "lambda_permissions_policy" {
  description = "Lambda permissions policy (for depends_on)"
  value       = aws_iam_role_policy.lambda_permissions.id
}
