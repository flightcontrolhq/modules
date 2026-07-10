################################################################################
# CloudFront Access Logs -> CloudWatch Logs (standard logging v2)
#
# CloudFront standard logging v2 delivers access logs to a CloudWatch Logs
# group via the vended-log delivery chain: a delivery source per distribution
# -> a shared delivery destination (the log group) -> a delivery per
# distribution connecting the two. Everything lives in us-east-1 because
# CloudFront is a global service. Created only when logging_enabled &&
# logging_destination == "cloudwatch"; the legacy S3 path stays in
# cloudfront.tf (module "cdn").
################################################################################

locals {
  cloudwatch_logging_enabled       = var.logging_enabled && var.logging_destination == "cloudwatch"
  cloudwatch_logging_distributions = local.cloudwatch_logging_enabled ? var.distributions : {}
}

resource "aws_cloudwatch_log_group" "access_logs" {
  count = local.cloudwatch_logging_enabled ? 1 : 0

  provider = aws.us_east_1

  name              = "/aws/cloudfront/${var.name}"
  retention_in_days = var.logging_retention_days

  tags = local.tags
}

resource "aws_cloudwatch_log_delivery_source" "access_logs" {
  for_each = local.cloudwatch_logging_distributions

  provider = aws.us_east_1

  name         = substr(replace("${var.name}-${each.key}-access-logs", "/[^a-zA-Z0-9-_.]/", "-"), 0, 60)
  log_type     = "ACCESS_LOGS"
  resource_arn = module.cdn.distribution_arns[each.key]

  tags = local.tags
}

resource "aws_cloudwatch_log_delivery_destination" "access_logs" {
  count = local.cloudwatch_logging_enabled ? 1 : 0

  provider = aws.us_east_1

  name          = substr(replace("${var.name}-access-logs-cw", "/[^a-zA-Z0-9-_.]/", "-"), 0, 60)
  output_format = "json"

  delivery_destination_configuration {
    destination_resource_arn = aws_cloudwatch_log_group.access_logs[0].arn
  }

  tags = local.tags
}

resource "aws_cloudwatch_log_delivery" "access_logs" {
  for_each = local.cloudwatch_logging_distributions

  provider = aws.us_east_1

  delivery_source_name     = aws_cloudwatch_log_delivery_source.access_logs[each.key].name
  delivery_destination_arn = aws_cloudwatch_log_delivery_destination.access_logs[0].arn

  tags = local.tags
}
