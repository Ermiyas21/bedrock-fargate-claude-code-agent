output "webhook_url" {
  description = "API Gateway webhook URL"
  value       = "${aws_apigatewayv2_stage.prod.invoke_url}/webhook"
}

output "function_name" {
  description = "Lambda function name"
  value       = aws_lambda_function.dispatcher.function_name
}
