locals {
  default_tags = {
    ManagedBy = "terraform"
    Module    = "compute/lambda"
  }

  tags = merge(local.default_tags, var.tags)

  log_group_name = coalesce(var.log_group_name, "/aws/lambda/${var.name}")

  role_name = coalesce(var.role_name, "${var.name}-lambda-role")

  managed_policy_arns = distinct(concat(
    var.attach_basic_execution_policy ? ["arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"] : [],
    var.attach_vpc_execution_policy && var.vpc_config != null ? ["arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"] : [],
    var.role_managed_policy_arns
  ))

  lambda_role_arn = var.create_role ? aws_iam_role.this[0].arn : var.role_arn

  permissions_map = {
    for idx, permission in var.permissions : tostring(idx) => permission
  }

  event_source_mappings_map = {
    for idx, mapping in var.event_source_mappings : tostring(idx) => mapping
  }
}
