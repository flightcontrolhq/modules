locals {
  region = coalesce(var.region, data.aws_region.current.region)

  default_tags = {
    ManagedBy = "terraform"
    Module    = "security/iam_policy"
  }

  tags = merge(local.default_tags, var.tags)

  policy_document = var.policy_json != null ? var.policy_json : (
    length(var.policy_statements) > 0 ? data.aws_iam_policy_document.structured[0].json : jsonencode({
      Version   = "2012-10-17"
      Statement = []
    })
  )
}
