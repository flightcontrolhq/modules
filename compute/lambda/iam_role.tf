################################################################################
# IAM Role
################################################################################

data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type = "Service"
      identifiers = [
        "lambda.amazonaws.com",
        "edgelambda.amazonaws.com"
      ]
    }
  }
}

resource "aws_iam_role" "this" {
  count = var.create_role ? 1 : 0

  name                 = local.role_name
  path                 = var.role_path
  assume_role_policy   = data.aws_iam_policy_document.lambda_assume_role.json
  permissions_boundary = var.role_permissions_boundary
  tags                 = local.tags
}

resource "aws_iam_role_policy_attachment" "managed" {
  for_each = var.create_role ? toset(local.managed_policy_arns) : toset([])

  role       = aws_iam_role.this[0].name
  policy_arn = each.value
}

resource "aws_iam_role_policy" "inline" {
  for_each = var.create_role ? var.role_inline_policies : {}

  name   = each.key
  role   = aws_iam_role.this[0].id
  policy = each.value
}
