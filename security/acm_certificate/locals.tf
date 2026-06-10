locals {
  region = coalesce(var.region, data.aws_region.current.id)
}

################################################################################
# Local Values
################################################################################

locals {
  default_tags = {
    ManagedBy = "terraform"
    Module    = "security/acm_certificate"
  }

  tags = merge(local.default_tags, var.tags)

  create_route53_records = var.route53_validation_records_creation_enabled && var.route53_zone_id != null
}
