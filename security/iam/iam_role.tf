################################################################################
# IAM Role
################################################################################

resource "aws_iam_role" "this" {
  name        = var.name
  name_prefix = var.name == null ? var.name_prefix : null
  description = var.description
  path        = var.path

  assume_role_policy    = local.assume_role_policy
  max_session_duration  = var.max_session_duration
  force_detach_policies = var.force_detach_policies
  permissions_boundary  = var.permission_boundary_arn

  tags = merge(local.tags, {
    Name = coalesce(var.name, var.name_prefix, "iam-role")
  })
}
