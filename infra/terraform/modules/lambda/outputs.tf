output "webhook_url" {
  description = "API Gateway webhook URL"
  value       = "${aws_apigatewayv2_stage.prod.invoke_url}/webhook"
}

output "function_name" {
  description = "Lambda function name"
  value       = aws_lambda_function.dispatcher.function_name
}

output "log_group_name" {
  description = "CloudWatch log group name for dispatcher Lambda"
  value       = aws_cloudwatch_log_group.dispatcher.name
}

output "log_group_arn" {
  description = "CloudWatch log group ARN for dispatcher Lambda"
  value       = aws_cloudwatch_log_group.dispatcher.arn
}
