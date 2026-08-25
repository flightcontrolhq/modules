################################################################################
# Log groups
#
# Two, deliberately: host-agent logs are Ravion's operational telemetry, while
# sandbox logs are customer output. Splitting them keeps retention, access and
# noise separable.
################################################################################

resource "aws_cloudwatch_log_group" "host" {
  name              = local.host_log_group
  retention_in_days = var.log_retention_days

  tags = merge(local.tags, { Name = local.host_log_group })
}

resource "aws_cloudwatch_log_group" "sandbox" {
  name              = local.sandbox_log_group
  retention_in_days = var.log_retention_days

  tags = merge(local.tags, { Name = local.sandbox_log_group })
}
