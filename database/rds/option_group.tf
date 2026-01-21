################################################################################
# RDS DB Option Group
################################################################################

resource "aws_db_option_group" "this" {
  count = local.create_option_group ? 1 : 0

  name                     = var.name
  engine_name              = var.engine
  major_engine_version     = local.option_group_engine_version
  option_group_description = "Option group for ${var.name} RDS instance"

  dynamic "option" {
    for_each = var.options
    content {
      option_name                    = option.value.option_name
      port                           = option.value.port
      version                        = option.value.version
      db_security_group_memberships  = option.value.db_security_group_memberships
      vpc_security_group_memberships = option.value.vpc_security_group_memberships

      dynamic "option_settings" {
        for_each = option.value.option_settings
        content {
          name  = option_settings.value.name
          value = option_settings.value.value
        }
      }
    }
  }

  tags = merge(local.tags, {
    Name = var.name
  })

  lifecycle {
    create_before_destroy = true
  }
}
