################################################################################
# Query Logging
################################################################################

resource "aws_cloudwatch_log_group" "query_logs" {
  provider = aws.us_east_1
  count    = var.query_logging_enabled && var.query_log_group_creation_enabled ? 1 : 0

  name              = local.query_log_group_name
  retention_in_days = local.query_log_group_retention_in_days
  tags              = local.tags
}

data "aws_iam_policy_document" "route53_query_logs" {
  count = var.query_logging_enabled && (var.query_log_group_creation_enabled || var.query_log_group_arn != null) ? 1 : 0

  statement {
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]

    principals {
      type        = "Service"
      identifiers = [local.route53_query_log_service_principal]
    }

    resources = [local.query_log_group_resource_arn]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = [local.route53_query_log_hosted_zone_arn]
    }
  }
}

resource "aws_cloudwatch_log_resource_policy" "route53_query_logs" {
  provider = aws.us_east_1
  count    = var.query_logging_enabled && (var.query_log_group_creation_enabled || var.query_log_group_arn != null) ? 1 : 0

  policy_name     = local.query_log_resource_policy_name
  policy_document = data.aws_iam_policy_document.route53_query_logs[0].json
}

resource "aws_route53_query_log" "this" {
  count = var.query_logging_enabled ? 1 : 0

  zone_id                  = local.zone_id
  cloudwatch_log_group_arn = local.query_log_group_arn

  depends_on = [aws_cloudwatch_log_resource_policy.route53_query_logs]

  lifecycle {
    precondition {
      condition     = !local.is_private_zone
      error_message = "Route53 query logging is supported only for public hosted zones."
    }

    precondition {
      condition     = var.query_log_group_creation_enabled || var.query_log_group_arn != null
      error_message = "query_log_group_arn is required when query_logging_enabled is true and query_log_group_creation_enabled is false."
    }
  }
}
