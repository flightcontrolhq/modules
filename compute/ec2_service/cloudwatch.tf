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
