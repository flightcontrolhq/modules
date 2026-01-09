################################################################################
# ElastiCache Parameter Group
################################################################################

resource "aws_elasticache_parameter_group" "this" {
  count = local.is_serverless ? 0 : 1

  name        = var.name
  family      = local.parameter_group_family
  description = "Parameter group for ${var.name} ElastiCache cluster"

  dynamic "parameter" {
    for_each = var.parameters
    content {
      name  = parameter.value.name
      value = parameter.value.value
    }
  }

  tags = merge(local.tags, {
    Name = var.name
  })

  lifecycle {
    create_before_destroy = true
  }
}
