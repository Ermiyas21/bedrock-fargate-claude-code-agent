# =============================================================================
# Budget Kill Switch — Auto-terminate tasks & revoke Bedrock access on overspend
# =============================================================================

data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
}

# -----------------------------------------------------
# CloudWatch Log Group for Kill Switch Lambda
# -----------------------------------------------------
resource "aws_cloudwatch_log_group" "kill_switch" {
  name              = "/aws/lambda/${var.prefix}-budget-kill-switch"
  retention_in_days = var.log_retention_days
  tags              = var.tags
}

# -----------------------------------------------------
# Lambda Function (Kill Switch)
# -----------------------------------------------------
data "archive_file" "kill_switch" {
  type        = "zip"
  source_dir  = var.lambda_source_dir
  output_path = "${path.module}/../../.build/kill-switch-package.zip"
  excludes    = ["__pycache__", "*.pyc"]
}

resource "aws_lambda_function" "kill_switch" {
  function_name    = "${var.prefix}-budget-kill-switch"
  role             = aws_iam_role.kill_switch.arn
  handler          = "kill_switch.handler"
  runtime          = "python3.12"
  timeout          = 60
  memory_size      = 128
  filename         = data.archive_file.kill_switch.output_path
  source_code_hash = data.archive_file.kill_switch.output_base64sha256

  environment {
    variables = {
      ECS_CLUSTER        = var.ecs_cluster_name
      ECS_TASK_ROLE_NAME = var.ecs_task_role_name
      DAILY_TOKEN_LIMIT  = tostring(var.daily_token_limit)
      DAILY_COST_LIMIT   = tostring(var.daily_cost_limit)
      BEDROCK_REGION     = var.bedrock_region
      SNS_TOPIC_ARN      = var.sns_topic_arn
    }
  }

  depends_on = [aws_cloudwatch_log_group.kill_switch]

  tags = var.tags
}

# -----------------------------------------------------
# Kill Switch Error Metric Filter
# -----------------------------------------------------
resource "aws_cloudwatch_log_metric_filter" "kill_switch_errors" {
  name           = "${var.prefix}-kill-switch-errors"
  log_group_name = aws_cloudwatch_log_group.kill_switch.name
  pattern        = "ERROR"

  metric_transformation {
    name          = "KillSwitchErrorCount"
    namespace     = "${var.prefix}/Lambda"
    value         = "1"
    default_value = "0"
  }
}

resource "aws_cloudwatch_metric_alarm" "kill_switch_errors" {
  alarm_name          = "${var.prefix}-kill-switch-errors"
  alarm_description   = "Kill switch Lambda is logging errors"
  namespace           = "${var.prefix}/Lambda"
  metric_name         = "KillSwitchErrorCount"
  statistic           = "Sum"
  period              = 300
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  treat_missing_data  = "notBreaching"

  alarm_actions = [var.sns_topic_arn]
  tags          = var.tags
}

# -----------------------------------------------------
# IAM Role for Kill Switch Lambda
# -----------------------------------------------------
resource "aws_iam_role" "kill_switch" {
  name = "${var.prefix}-kill-switch-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "kill_switch_basic" {
  role       = aws_iam_role.kill_switch.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "kill_switch_permissions" {
  name = "${var.prefix}-kill-switch-permissions"
  role = aws_iam_role.kill_switch.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "StopEcsTasks"
        Effect = "Allow"
        Action = [
          "ecs:ListTasks",
          "ecs:StopTask",
          "ecs:DescribeTasks"
        ]
        Resource = "*"
        Condition = {
          ArnLike = {
            "ecs:cluster" = "arn:aws:ecs:${var.aws_region}:${local.account_id}:cluster/${var.ecs_cluster_name}"
          }
        }
      },
      {
        Sid    = "RevokeBedrockAccess"
        Effect = "Allow"
        Action = [
          "iam:PutRolePolicy",
          "iam:GetRolePolicy"
        ]
        Resource = "arn:aws:iam::${local.account_id}:role/${var.ecs_task_role_name}"
      },
      {
        Sid    = "CloudWatchMetrics"
        Effect = "Allow"
        Action = [
          "cloudwatch:GetMetricData",
          "cloudwatch:GetMetricStatistics"
        ]
        Resource = "*"
      },
      {
        Sid      = "SNSNotify"
        Effect   = "Allow"
        Action   = "sns:Publish"
        Resource = var.sns_topic_arn
      }
    ]
  })
}

# -----------------------------------------------------
# SNS Subscription — trigger Lambda on budget alarm
# -----------------------------------------------------
resource "aws_sns_topic_subscription" "kill_switch" {
  topic_arn = var.sns_topic_arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.kill_switch.arn
}

resource "aws_lambda_permission" "sns_invoke" {
  statement_id  = "AllowSNSInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.kill_switch.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = var.sns_topic_arn
}

# -----------------------------------------------------
# Scheduled check (every 5 minutes)
# -----------------------------------------------------
resource "aws_cloudwatch_event_rule" "budget_check" {
  name                = "${var.prefix}-budget-check"
  description         = "Periodic budget check for Bedrock usage"
  schedule_expression = "rate(5 minutes)"
  tags                = var.tags
}

resource "aws_cloudwatch_event_target" "kill_switch" {
  rule      = aws_cloudwatch_event_rule.budget_check.name
  target_id = "kill-switch-lambda"
  arn       = aws_lambda_function.kill_switch.arn
}

resource "aws_lambda_permission" "eventbridge_invoke" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.kill_switch.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.budget_check.arn
}
