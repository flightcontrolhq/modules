################################################################################
# CloudFront access logs -> CloudWatch Logs (standard logging v2)
#
# CloudFront is a global service; its log delivery is always configured in
# us-east-1. Access logs for every distribution are delivered to a single
# CloudWatch log group so the Ravion module Logs tab can query them through
# CloudWatch Logs Insights.
#
# The log group name is deterministic (`/aws/cloudfront/<name>/access`), which
# lets the module definition's `ui.logs` template the group from
# `module.input.name` directly — no stack-output round-trip needed before the
# Logs tab can resolve its source.
################################################################################

resource "aws_cloudwatch_log_group" "cloudfront_access" {
  provider          = aws.us_east_1
  name              = "/aws/cloudfront/${var.name}/access"
  retention_in_days = var.cloudfront_access_log_retention_days
  tags              = local.tags
}

# Resource policy granting the vended-log delivery service permission to write
# to the destination log group (required for same-account CloudWatch Logs
# delivery). Scoped to this account via aws:SourceAccount.
data "aws_iam_policy_document" "cloudfront_access_delivery" {
  statement {
    sid    = "AWSLogDeliveryWrite"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["delivery.logs.amazonaws.com"]
    }

    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]

    resources = ["${aws_cloudwatch_log_group.cloudfront_access.arn}:*"]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }
}

resource "aws_cloudwatch_log_resource_policy" "cloudfront_access" {
  provider        = aws.us_east_1
  policy_name     = substr(replace("${var.name}-cf-access-delivery", "/[^a-zA-Z0-9-_]/", "-"), 0, 60)
  policy_document = data.aws_iam_policy_document.cloudfront_access_delivery.json
}

# One delivery source per distribution; all share the single destination.
resource "aws_cloudwatch_log_delivery_source" "cloudfront_access" {
  for_each = module.cdn.distribution_arns

  provider     = aws.us_east_1
  name         = substr(replace("${var.name}-${each.key}-cf-access", "/[^a-zA-Z0-9-_]/", "-"), 0, 60)
  log_type     = "ACCESS_LOGS"
  resource_arn = each.value
  tags         = local.tags
}

resource "aws_cloudwatch_log_delivery_destination" "cloudfront_access" {
  provider      = aws.us_east_1
  name          = substr(replace("${var.name}-cf-access", "/[^a-zA-Z0-9-_]/", "-"), 0, 60)
  output_format = "json"

  delivery_destination_configuration {
    destination_resource_arn = aws_cloudwatch_log_group.cloudfront_access.arn
  }

  tags = local.tags
}

resource "aws_cloudwatch_log_delivery" "cloudfront_access" {
  for_each = aws_cloudwatch_log_delivery_source.cloudfront_access

  provider                 = aws.us_east_1
  delivery_source_name     = each.value.name
  delivery_destination_arn = aws_cloudwatch_log_delivery_destination.cloudfront_access.arn

  # The destination log group must accept delivery-service writes first.
  depends_on = [aws_cloudwatch_log_resource_policy.cloudfront_access]

  tags = local.tags
}
