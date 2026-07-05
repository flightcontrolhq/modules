################################################################################
# CloudWatch Log Group
#
# App logs from every instance land here: the container runtime uses the
# Docker awslogs driver and the manual runtime ships the app log file
# through the CloudWatch agent. Streams are prefixed with the instance ID.
################################################################################

resource "aws_cloudwatch_log_group" "app" {
  name              = local.log_group_name
  retention_in_days = var.log_retention_in_days

  tags = local.tags
}
