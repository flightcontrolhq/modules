################################################################################
# Cluster Parameter Group
################################################################################

resource "aws_rds_cluster_parameter_group" "this" {
  count = var.create_cluster_parameter_group ? 1 : 0

  name        = var.name
  family      = coalesce(var.cluster_parameter_group_family, local.default_parameter_group_family)
  description = "Cluster parameter group for ${var.name} Aurora cluster"

  dynamic "parameter" {
    for_each = var.cluster_parameters
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

################################################################################
# DB Parameter Group (instance-level)
################################################################################

resource "aws_db_parameter_group" "this" {
  count = var.create_db_parameter_group ? 1 : 0

  name        = var.name
  family      = coalesce(var.db_parameter_group_family, local.default_parameter_group_family)
  description = "DB parameter group for ${var.name} Aurora instances"

  dynamic "parameter" {
    for_each = var.db_parameters
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
