################################################################################
# Logical dump schedule, destination, and freshness alarm
################################################################################

resource "aws_cloudwatch_log_metric_filter" "backup_dump_success" {
  count = var.backup_dump_enabled && var.backup_dump_failure_alarm_enabled ? 1 : 0

  name           = "${var.name}-backup-dump-success"
  log_group_name = aws_cloudwatch_log_group.app.name
  pattern        = "\"RAVION_BACKUP_SUCCESS\""

  metric_transformation {
    name      = "${var.name}-backup-dump-success"
    namespace = "Ravion/EC2Service"
    value     = "1"
  }
}

resource "aws_cloudwatch_metric_alarm" "backup_dump_failure" {
  count = var.backup_dump_enabled && var.backup_dump_failure_alarm_enabled ? 1 : 0

  alarm_name          = "${var.name}-backup-dump-failure"
  alarm_description   = "No successful logical dump has been recorded for ${var.name} within the configured maximum interval of ${var.backup_dump_max_interval_hours} hours."
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = local.backup_dump_alarm_evaluation_periods
  metric_name         = aws_cloudwatch_log_metric_filter.backup_dump_success[0].metric_transformation[0].name
  namespace           = "Ravion/EC2Service"
  period              = local.backup_dump_alarm_period
  statistic           = "Sum"
  threshold           = 1
  treat_missing_data  = "breaching"
}
