################################################################################
# Query Logging
################################################################################

resource "aws_route53_query_log" "this" {
  count = var.enable_query_logging ? 1 : 0

  zone_id                  = local.zone_id
  cloudwatch_log_group_arn = var.query_log_group_arn

  lifecycle {
    precondition {
      condition     = var.query_log_group_arn != null
      error_message = "query_log_group_arn is required when enable_query_logging is true."
    }
  }
}
