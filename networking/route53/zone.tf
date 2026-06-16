################################################################################
# Public Hosted Zone
################################################################################

resource "aws_route53_zone" "public" {
  count = local.create_public_zone ? 1 : 0

  name              = var.name
  comment           = var.comment
  force_destroy     = var.record_force_destroy_enabled
  delegation_set_id = var.delegation_set_id

  tags = local.tags

  lifecycle {
    precondition {
      condition     = var.name != null
      error_message = "var.name is required when zone_creation_enabled is true."
    }
  }
}

################################################################################
# Private Hosted Zone
################################################################################

resource "aws_route53_zone" "private" {
  count = var.zone_creation_enabled && var.private_zone_enabled ? 1 : 0

  name          = var.name
  comment       = var.comment
  force_destroy = var.record_force_destroy_enabled

  dynamic "vpc" {
    for_each = var.vpc_associations
    content {
      vpc_id     = vpc.value.vpc_id
      vpc_region = vpc.value.vpc_region
    }
  }

  tags = local.tags

  lifecycle {
    precondition {
      condition     = var.name != null
      error_message = "var.name is required when zone_creation_enabled is true."
    }
    precondition {
      condition     = length(var.vpc_associations) > 0
      error_message = "At least one VPC association is required for a private hosted zone."
    }

    ignore_changes = [vpc]
  }
}
