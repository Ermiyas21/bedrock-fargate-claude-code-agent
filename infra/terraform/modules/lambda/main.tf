# =============================================================================
# Lambda Dispatcher + API Gateway (HTTP API)
# =============================================================================

# -----------------------------------------------------
# Lambda Function
# -----------------------------------------------------
data "archive_file" "lambda" {
  type        = "zip"
  source_dir  = var.lambda_source_dir
  output_path = "${path.module}/../../.build/lambda-package.zip"
  excludes    = ["__pycache__", "*.pyc"]
}

resource "aws_lambda_function" "dispatcher" {
  function_name    = "${var.prefix}-dispatcher"
  role             = var.lambda_role_arn
  handler          = "handler.handler"
  runtime          = "python3.12"
  timeout          = 30
  memory_size      = 256
  filename         = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256

  environment {
    variables = {
      ECS_CLUSTER         = var.ecs_cluster_name
      ECS_TASK_DEFINITION = var.ecs_task_definition_family
      SUBNETS             = join(",", var.subnet_ids)
      SECURITY_GROUPS     = join(",", var.security_group_ids)
      CONTAINER_NAME      = "claude-code-agent"
      TICKET_BUCKET       = var.ticket_bucket_id
    }
  }

  tags = var.tags
}

# -----------------------------------------------------
# API Gateway v2 (HTTP API)
# -----------------------------------------------------
resource "aws_apigatewayv2_api" "webhook" {
  name          = "${var.prefix}-webhook-api"
  protocol_type = "HTTP"
  tags          = var.tags
}

resource "aws_apigatewayv2_integration" "lambda" {
  api_id                 = aws_apigatewayv2_api.webhook.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.dispatcher.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "webhook" {
  api_id    = aws_apigatewayv2_api.webhook.id
  route_key = "POST /webhook"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

resource "aws_apigatewayv2_stage" "prod" {
  api_id      = aws_apigatewayv2_api.webhook.id
  name        = "prod"
  auto_deploy = true
  tags        = var.tags
}

# Grant API Gateway permission to invoke Lambda
resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.dispatcher.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.webhook.execution_arn}/*/*"
}
