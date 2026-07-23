# =============================================================================
# CloudWatch Alarms + SNS Topic + CloudTrail
# =============================================================================

# -----------------------------------------------------
# SNS Topic for alerts
# -----------------------------------------------------
resource "aws_sns_topic" "alerts" {
  name = "${var.prefix}-alerts"
  tags = var.tags
}

resource "aws_sns_topic_subscription" "email" {
  count     = var.alarm_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

# -----------------------------------------------------
# CloudTrail — Bedrock API audit logging
# -----------------------------------------------------
resource "aws_s3_bucket" "trail_logs" {
  bucket = "${var.prefix}-cloudtrail-${data.aws_caller_identity.current.account_id}"
  tags   = var.tags
}

resource "aws_s3_bucket_policy" "trail_logs" {
  bucket = aws_s3_bucket.trail_logs.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSCloudTrailAclCheck"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.trail_logs.arn
      },
      {
        Sid    = "AWSCloudTrailWrite"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.trail_logs.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      }
    ]
  })
}

resource "aws_s3_bucket_public_access_block" "trail_logs" {
  bucket = aws_s3_bucket.trail_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_cloudtrail" "bedrock_audit" {
  name                          = "${var.prefix}-bedrock-audit"
  s3_bucket_name                = aws_s3_bucket.trail_logs.id
  include_global_service_events = true
  is_multi_region_trail         = true
  enable_logging                = true

  advanced_event_selector {
    name = "Bedrock model invocations"

    field_selector {
      field  = "eventCategory"
      equals = ["Data"]
    }

    field_selector {
      field  = "resources.type"
      equals = ["AWS::Bedrock::Model"]
    }
  }

  tags = var.tags

  depends_on = [aws_s3_bucket_policy.trail_logs]
}

# -----------------------------------------------------
# Alarm: Task failure rate
# -----------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "task_failures" {
  alarm_name          = "${var.prefix}-task-failures"
  alarm_description   = "Alert when Claude Code agent tasks fail"
  namespace           = "ECS/ContainerInsights"
  metric_name         = "TaskFailureCount"
  statistic           = "Sum"
  period              = 300
  threshold           = 3
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1

  dimensions = {
    ClusterName = var.ecs_cluster_name
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  tags          = var.tags
}

# -----------------------------------------------------
# Alarm: Long-running tasks (>30 minutes)
# -----------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "long_running_task" {
  alarm_name          = "${var.prefix}-long-running-task"
  alarm_description   = "Alert when a task runs longer than 30 minutes"
  namespace           = "ECS/ContainerInsights"
  metric_name         = "RunningTaskCount"
  statistic           = "Maximum"
  period              = 1800
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2

  dimensions = {
    ClusterName = var.ecs_cluster_name
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  tags          = var.tags
}

# -----------------------------------------------------
# Alarm: High Bedrock invocation count
# -----------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "bedrock_invocations" {
  alarm_name          = "${var.prefix}-bedrock-invocations"
  alarm_description   = "Alert when daily Bedrock invocations exceed threshold"
  namespace           = "AWS/Bedrock"
  metric_name         = "Invocations"
  statistic           = "Sum"
  period              = 86400
  threshold           = 500
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1

  alarm_actions = [aws_sns_topic.alerts.arn]
  tags          = var.tags
}

# -----------------------------------------------------
# Alarm: Bedrock token usage (triggers kill switch)
# -----------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "bedrock_token_usage" {
  alarm_name          = "${var.prefix}-bedrock-token-budget"
  alarm_description   = "Budget exceeded — triggers kill switch Lambda"
  namespace           = "AWS/Bedrock"
  metric_name         = "InputTokenCount"
  statistic           = "Sum"
  period              = 86400
  threshold           = 5000000
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1

  alarm_actions = [var.sns_topic_arn != "" ? var.sns_topic_arn : aws_sns_topic.alerts.arn]
  tags          = var.tags
}

# -----------------------------------------------------
# Alarm: Bedrock invocation errors
# -----------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "bedrock_errors" {
  alarm_name          = "${var.prefix}-bedrock-errors"
  alarm_description   = "Bedrock model invocation errors detected"
  namespace           = "AWS/Bedrock"
  metric_name         = "InvocationClientErrors"
  statistic           = "Sum"
  period              = 300
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.alerts.arn]
  tags          = var.tags
}

resource "aws_cloudwatch_metric_alarm" "bedrock_throttles" {
  alarm_name          = "${var.prefix}-bedrock-throttles"
  alarm_description   = "Bedrock model invocation throttling detected"
  namespace           = "AWS/Bedrock"
  metric_name         = "InvocationThrottles"
  statistic           = "Sum"
  period              = 300
  threshold           = 5
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.alerts.arn]
  tags          = var.tags
}

# -----------------------------------------------------
# Alarm: Lambda dispatcher errors (AWS-native metric)
# -----------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "${var.prefix}-lambda-errors"
  alarm_description   = "Lambda function invocation errors"
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  statistic           = "Sum"
  period              = 300
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = var.lambda_function_name
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  tags          = var.tags
}

# -----------------------------------------------------
# Alarm: Lambda dispatcher duration (approaching timeout)
# -----------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "lambda_duration" {
  alarm_name          = "${var.prefix}-lambda-high-duration"
  alarm_description   = "Lambda dispatcher approaching timeout"
  namespace           = "AWS/Lambda"
  metric_name         = "Duration"
  statistic           = "Maximum"
  period              = 300
  threshold           = 25000
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = var.lambda_function_name
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  tags          = var.tags
}

# -----------------------------------------------------
# ECS Agent Error Metric Filter (from task logs)
# -----------------------------------------------------
resource "aws_cloudwatch_log_metric_filter" "ecs_agent_errors" {
  name           = "${var.prefix}-ecs-agent-errors"
  log_group_name = var.ecs_log_group_name
  pattern        = "\"ERROR\" \"WARNING: Claude Code exited\""

  metric_transformation {
    name          = "AgentErrorCount"
    namespace     = "${var.prefix}/ECS"
    value         = "1"
    default_value = "0"
  }
}

resource "aws_cloudwatch_metric_alarm" "ecs_agent_errors" {
  alarm_name          = "${var.prefix}-ecs-agent-errors"
  alarm_description   = "Claude Code agent container is logging errors"
  namespace           = "${var.prefix}/ECS"
  metric_name         = "AgentErrorCount"
  statistic           = "Sum"
  period              = 300
  threshold           = 3
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.alerts.arn]
  tags          = var.tags
}

# -----------------------------------------------------
# CloudWatch Dashboard — Lambda & Bedrock Observability
# -----------------------------------------------------
resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${var.prefix}-observability"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          title = "Lambda Dispatcher — Invocations & Errors"
          metrics = [
            ["AWS/Lambda", "Invocations", "FunctionName", var.lambda_function_name, { stat = "Sum", period = 300 }],
            ["AWS/Lambda", "Errors", "FunctionName", var.lambda_function_name, { stat = "Sum", period = 300, color = "#d62728" }],
            ["AWS/Lambda", "Throttles", "FunctionName", var.lambda_function_name, { stat = "Sum", period = 300, color = "#ff7f0e" }],
          ]
          view   = "timeSeries"
          region = var.aws_region
          period = 300
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          title = "Lambda Dispatcher — Duration"
          metrics = [
            ["AWS/Lambda", "Duration", "FunctionName", var.lambda_function_name, { stat = "Average", period = 300 }],
            ["AWS/Lambda", "Duration", "FunctionName", var.lambda_function_name, { stat = "Maximum", period = 300, color = "#d62728" }],
          ]
          view   = "timeSeries"
          region = var.aws_region
          period = 300
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        properties = {
          title = "Bedrock — Invocations & Errors"
          metrics = [
            ["AWS/Bedrock", "Invocations", { stat = "Sum", period = 300 }],
            ["AWS/Bedrock", "InvocationClientErrors", { stat = "Sum", period = 300, color = "#d62728" }],
            ["AWS/Bedrock", "InvocationServerErrors", { stat = "Sum", period = 300, color = "#9467bd" }],
            ["AWS/Bedrock", "InvocationThrottles", { stat = "Sum", period = 300, color = "#ff7f0e" }],
          ]
          view   = "timeSeries"
          region = var.aws_region
          period = 300
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 6
        width  = 12
        height = 6
        properties = {
          title = "Bedrock — Token Usage"
          metrics = [
            ["AWS/Bedrock", "InputTokenCount", { stat = "Sum", period = 3600 }],
            ["AWS/Bedrock", "OutputTokenCount", { stat = "Sum", period = 3600, color = "#2ca02c" }],
          ]
          view   = "timeSeries"
          region = var.aws_region
          period = 3600
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 12
        width  = 12
        height = 6
        properties = {
          title = "Bedrock — Latency"
          metrics = [
            ["AWS/Bedrock", "InvocationLatency", { stat = "Average", period = 300 }],
            ["AWS/Bedrock", "InvocationLatency", { stat = "p99", period = 300, color = "#d62728" }],
          ]
          view   = "timeSeries"
          region = var.aws_region
          period = 300
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 12
        width  = 12
        height = 6
        properties = {
          title = "ECS — Task Status"
          metrics = [
            ["ECS/ContainerInsights", "RunningTaskCount", "ClusterName", var.ecs_cluster_name, { stat = "Maximum", period = 300 }],
            ["ECS/ContainerInsights", "TaskFailureCount", "ClusterName", var.ecs_cluster_name, { stat = "Sum", period = 300, color = "#d62728" }],
          ]
          view   = "timeSeries"
          region = var.aws_region
          period = 300
        }
      },
      {
        type   = "log"
        x      = 0
        y      = 18
        width  = 24
        height = 6
        properties = {
          title  = "Lambda Dispatcher — Recent Errors"
          query  = "SOURCE '${var.lambda_log_group_name}' | fields @timestamp, @message | filter @message like /ERROR/ | sort @timestamp desc | limit 20"
          region = var.aws_region
          view   = "table"
        }
      },
      {
        type   = "log"
        x      = 0
        y      = 24
        width  = 24
        height = 6
        properties = {
          title  = "ECS Agent — Recent Errors"
          query  = "SOURCE '${var.ecs_log_group_name}' | fields @timestamp, @message | filter @message like /ERROR|WARN|exited with code/ | sort @timestamp desc | limit 20"
          region = var.aws_region
          view   = "table"
        }
      }
    ]
  })
}

data "aws_caller_identity" "current" {}
