output "kill_switch_function_name" {
  description = "Kill switch Lambda function name"
  value       = aws_lambda_function.kill_switch.function_name
}

output "kill_switch_function_arn" {
  description = "Kill switch Lambda function ARN"
  value       = aws_lambda_function.kill_switch.arn
}
