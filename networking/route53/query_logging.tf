################################################################################
# Query Logging
################################################################################

resource "aws_route53_query_log" "this" {
  count = var.query_logging_enabled ? 1 : 0

  zone_id                  = local.zone_id
  cloudwatch_log_group_arn = var.query_log_group_arn

  lifecycle {
    precondition {
      condition     = var.query_log_group_arn != null
      error_message = "query_log_group_arn is required when query_logging_enabled is true."
    }
  }
}
