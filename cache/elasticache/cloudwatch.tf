################################################################################
# CloudWatch Alarms
################################################################################

resource "aws_cloudwatch_metric_alarm" "cpu_utilization" {
  count = local.create_cloudwatch_alarms ? 1 : 0

  alarm_name          = "${var.name}-elasticache-cpu-utilization"
  alarm_description   = "ElastiCache CPU utilization for ${var.name}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ElastiCache"
  period              = 300
  statistic           = "Average"
  threshold           = var.cloudwatch_alarm_cpu_threshold

  dimensions = {
    CacheClusterId = local.cloudwatch_dimension_value
  }

  alarm_actions = var.cloudwatch_alarm_actions
  ok_actions    = var.cloudwatch_ok_actions

  tags = local.tags
}

resource "aws_cloudwatch_metric_alarm" "database_memory_usage" {
  count = local.create_cloudwatch_alarms && local.is_redis_compatible ? 1 : 0

  alarm_name          = "${var.name}-elasticache-memory-usage"
  alarm_description   = "ElastiCache database memory usage for ${var.name}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "DatabaseMemoryUsagePercentage"
  namespace           = "AWS/ElastiCache"
  period              = 300
  statistic           = "Average"
  threshold           = var.cloudwatch_alarm_memory_threshold

  dimensions = {
    CacheClusterId = local.cloudwatch_dimension_value
  }

  alarm_actions = var.cloudwatch_alarm_actions
  ok_actions    = var.cloudwatch_ok_actions

  tags = local.tags
}

resource "aws_cloudwatch_metric_alarm" "current_connections" {
  count = local.create_cloudwatch_alarms ? 1 : 0

  alarm_name          = "${var.name}-elasticache-current-connections"
  alarm_description   = "ElastiCache current connections for ${var.name}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CurrConnections"
  namespace           = "AWS/ElastiCache"
  period              = 300
  statistic           = "Average"
  threshold           = var.cloudwatch_alarm_connections_threshold

  dimensions = {
    CacheClusterId = local.cloudwatch_dimension_value
  }

  alarm_actions = var.cloudwatch_alarm_actions
  ok_actions    = var.cloudwatch_ok_actions

  tags = local.tags
}

resource "aws_cloudwatch_metric_alarm" "evictions" {
  count = local.create_cloudwatch_alarms ? 1 : 0

  alarm_name          = "${var.name}-elasticache-evictions"
  alarm_description   = "ElastiCache evictions for ${var.name}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "Evictions"
  namespace           = "AWS/ElastiCache"
  period              = 300
  statistic           = "Sum"
  threshold           = 100

  dimensions = {
    CacheClusterId = local.cloudwatch_dimension_value
  }

  alarm_actions = var.cloudwatch_alarm_actions
  ok_actions    = var.cloudwatch_ok_actions

  tags = local.tags
}
