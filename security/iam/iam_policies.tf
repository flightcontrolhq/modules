################################################################################
# Managed Policy Attachments
################################################################################

resource "aws_iam_role_policy_attachment" "managed" {
  for_each = toset(var.managed_policy_arns)

  role       = aws_iam_role.this.name
  policy_arn = each.value
}

################################################################################
# Inline Policies (JSON)
################################################################################

resource "aws_iam_role_policy" "inline" {
  for_each = var.inline_policies

  name   = each.key
  role   = aws_iam_role.this.id
  policy = each.value
}

################################################################################
# Inline Policy Statements (Structured)
################################################################################

data "aws_iam_policy_document" "inline_statements" {
  count = local.has_inline_policy_statements ? 1 : 0

  dynamic "statement" {
    for_each = var.inline_policy_statements
    content {
      sid       = statement.value.sid
      effect    = statement.value.effect
      actions   = statement.value.actions
      resources = statement.value.resources

      dynamic "condition" {
        for_each = statement.value.conditions
        content {
          test     = condition.value.test
          variable = condition.value.variable
          values   = condition.value.values
        }
      }
    }
  }
}

resource "aws_iam_role_policy" "statements" {
  count = local.has_inline_policy_statements ? 1 : 0

  name   = "inline-statements"
  role   = aws_iam_role.this.id
  policy = data.aws_iam_policy_document.inline_statements[0].json
}
