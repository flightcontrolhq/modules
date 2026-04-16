################################################################################
# CloudWatch Alarms
################################################################################

resource "aws_cloudwatch_metric_alarm" "read_throttle" {
  count = var.create_cloudwatch_alarms ? 1 : 0

  alarm_name          = "${var.name}-dynamodb-read-throttle"
  alarm_description   = "DynamoDB read throttle events for ${var.name}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.cloudwatch_alarm_evaluation_periods
  metric_name         = "ReadThrottleEvents"
  namespace           = "AWS/DynamoDB"
  period              = var.cloudwatch_alarm_period
  statistic           = "Sum"
  threshold           = var.cloudwatch_read_throttle_threshold
  treat_missing_data  = "notBreaching"

  dimensions = {
    TableName = aws_dynamodb_table.this.name
  }

  alarm_actions = var.cloudwatch_alarm_actions
  ok_actions    = var.cloudwatch_ok_actions

  tags = local.tags
}

resource "aws_cloudwatch_metric_alarm" "write_throttle" {
  count = var.create_cloudwatch_alarms ? 1 : 0

  alarm_name          = "${var.name}-dynamodb-write-throttle"
  alarm_description   = "DynamoDB write throttle events for ${var.name}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.cloudwatch_alarm_evaluation_periods
  metric_name         = "WriteThrottleEvents"
  namespace           = "AWS/DynamoDB"
  period              = var.cloudwatch_alarm_period
  statistic           = "Sum"
  threshold           = var.cloudwatch_write_throttle_threshold
  treat_missing_data  = "notBreaching"

  dimensions = {
    TableName = aws_dynamodb_table.this.name
  }

  alarm_actions = var.cloudwatch_alarm_actions
  ok_actions    = var.cloudwatch_ok_actions

  tags = local.tags
}

resource "aws_cloudwatch_metric_alarm" "system_errors" {
  count = var.create_cloudwatch_alarms ? 1 : 0

  alarm_name          = "${var.name}-dynamodb-system-errors"
  alarm_description   = "DynamoDB system errors for ${var.name}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.cloudwatch_alarm_evaluation_periods
  metric_name         = "SystemErrors"
  namespace           = "AWS/DynamoDB"
  period              = var.cloudwatch_alarm_period
  statistic           = "Sum"
  threshold           = var.cloudwatch_system_errors_threshold
  treat_missing_data  = "notBreaching"

  dimensions = {
    TableName = aws_dynamodb_table.this.name
  }

  alarm_actions = var.cloudwatch_alarm_actions
  ok_actions    = var.cloudwatch_ok_actions

  tags = local.tags
}
