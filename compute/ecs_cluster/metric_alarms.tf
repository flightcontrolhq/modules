################################################################################
# CloudWatch metric alarms → Ravion notifications
#
# Cluster-level CPU/memory alarms. When notifications are enabled, Ravion
# provisions an SNS topic per alarm (via the ravion_metric_alarm resource) and
# records its notification routing. The CloudWatch alarm's alarm_actions are
# wired to the returned topic ARN, so a breach publishes to Ravion, which fetches
# the metric, renders the chart, and delivers the notification.
################################################################################

locals {
  metric_alarms_enabled = var.notifications_enabled && var.notification_template_id != "" && var.notification_channel_ref != ""
}

resource "ravion_metric_alarm" "cpu" {
  count = local.metric_alarms_enabled ? 1 : 0

  alarm_name               = "${aws_ecs_cluster.this.name}-ecs-cluster-cpu-utilization"
  aws_account_id           = data.aws_caller_identity.current.account_id
  region                   = local.region
  notification_template_id = var.notification_template_id
  channel_ref              = var.notification_channel_ref
}

resource "aws_cloudwatch_metric_alarm" "cluster_cpu_utilization" {
  count = local.metric_alarms_enabled ? 1 : 0

  alarm_name          = "${aws_ecs_cluster.this.name}-ecs-cluster-cpu-utilization"
  alarm_description   = "ECS cluster CPU utilization for ${aws_ecs_cluster.this.name}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = var.alarm_period
  statistic           = "Average"
  threshold           = var.cpu_alarm_threshold
  treat_missing_data  = "notBreaching"

  dimensions = {
    ClusterName = aws_ecs_cluster.this.name
  }

  alarm_actions = [ravion_metric_alarm.cpu[0].sns_topic_arn]

  tags = local.tags
}

resource "ravion_metric_alarm" "memory" {
  count = local.metric_alarms_enabled ? 1 : 0

  alarm_name               = "${aws_ecs_cluster.this.name}-ecs-cluster-memory-utilization"
  aws_account_id           = data.aws_caller_identity.current.account_id
  region                   = local.region
  notification_template_id = var.notification_template_id
  channel_ref              = var.notification_channel_ref
}

resource "aws_cloudwatch_metric_alarm" "cluster_memory_utilization" {
  count = local.metric_alarms_enabled ? 1 : 0

  alarm_name          = "${aws_ecs_cluster.this.name}-ecs-cluster-memory-utilization"
  alarm_description   = "ECS cluster memory utilization for ${aws_ecs_cluster.this.name}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name         = "MemoryUtilization"
  namespace           = "AWS/ECS"
  period              = var.alarm_period
  statistic           = "Average"
  threshold           = var.memory_alarm_threshold
  treat_missing_data  = "notBreaching"

  dimensions = {
    ClusterName = aws_ecs_cluster.this.name
  }

  alarm_actions = [ravion_metric_alarm.memory[0].sns_topic_arn]

  tags = local.tags
}
