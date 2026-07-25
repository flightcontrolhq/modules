resource "aws_iam_policy" "this" {
  name        = var.name
  description = var.description
  path        = var.path
  policy      = local.policy_document
  tags        = local.tags

  lifecycle {
    precondition {
      condition     = var.policy_json != null || length(var.policy_statements) > 0
      error_message = "Provide at least one policy_statement or a policy_json document."
    }
  }
}
