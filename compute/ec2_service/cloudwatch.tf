################################################################################
# CloudWatch Log Group
#
# App stdout and stderr from every instance land here. Supervisord writes
# each release to its own file, and the CloudWatch agent publishes it to a
# stream scoped by deployment ID and instance ID.
################################################################################

resource "aws_cloudwatch_log_group" "app" {
  name              = local.log_group_name
  retention_in_days = var.log_retention_in_days

  tags = local.tags
}

################################################################################
# Unexpected Process Exits
#
# The supervisord event listener on each instance writes one JSON line per
# unexpected exit. This filter turns those lines into a metric, so crashes
# that happen after the process passed startsecs (which startretries does
# not cover) are alarmable.
################################################################################

resource "aws_cloudwatch_log_metric_filter" "process_exit" {
  name           = "${var.name}-unexpected-process-exits"
  log_group_name = aws_cloudwatch_log_group.app.name
  pattern        = "{ $.event = \"process_exit\" && $.expected IS FALSE }"

  metric_transformation {
    name       = local.process_exit_metric_name
    namespace  = local.process_exit_metric_namespace
    value      = "1"
    unit       = "Count"
    dimensions = { ServiceName = "$.service" }
  }
}

resource "aws_cloudwatch_metric_alarm" "process_exit" {
  count = var.process_exit_alarm_enabled ? 1 : 0

  alarm_name          = "${var.name}-unexpected-process-exits"
  alarm_description   = "Unexpected exits of the supervised ${var.name} app process"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = var.process_exit_alarm_evaluation_periods
  metric_name         = aws_cloudwatch_log_metric_filter.process_exit.metric_transformation[0].name
  namespace           = aws_cloudwatch_log_metric_filter.process_exit.metric_transformation[0].namespace
  period              = var.process_exit_alarm_period
  statistic           = "Sum"
  threshold           = var.process_exit_alarm_threshold
  treat_missing_data  = "notBreaching"

  dimensions = {
    ServiceName = var.name
  }

  alarm_actions = var.cloudwatch_alarm_actions
  ok_actions    = var.cloudwatch_ok_actions

  tags = local.tags
}
