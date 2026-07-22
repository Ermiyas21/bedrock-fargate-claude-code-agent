# =============================================================================
# CloudWatch Alarms + SNS Topic
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
resource "aws_cloudwatch_metric_alarm" "bedrock_spend" {
  alarm_name          = "${var.prefix}-bedrock-spend"
  alarm_description   = "Alert when daily Bedrock spend exceeds threshold"
  namespace           = "AWS/Bedrock"
  metric_name         = "InvocationCount"
  statistic           = "Sum"
  period              = 86400
  threshold           = 500
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1

  alarm_actions = [aws_sns_topic.alerts.arn]
  tags          = var.tags
}
