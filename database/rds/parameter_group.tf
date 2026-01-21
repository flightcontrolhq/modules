################################################################################
# RDS DB Parameter Group
################################################################################

resource "aws_db_parameter_group" "this" {
  count = local.create_parameter_group ? 1 : 0

  name        = var.name
  family      = local.parameter_group_family
  description = "Parameter group for ${var.name} RDS instance"

  dynamic "parameter" {
    for_each = var.parameters
    content {
      name         = parameter.value.name
      value        = parameter.value.value
      apply_method = parameter.value.apply_method
    }
  }

  tags = merge(local.tags, {
    Name = var.name
  })

  lifecycle {
    create_before_destroy = true
  }
}
