################################################################################
# Local Values
################################################################################

locals {
  default_tags = {
    ManagedBy = "terraform"
    Module    = "security/acm_certificate"
  }

  tags = merge(local.default_tags, var.tags)

  create_route53_records = var.create_route53_validation_records && var.route53_zone_id != null
}
