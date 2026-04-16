################################################################################
# Local Values
################################################################################

locals {
  default_tags = {
    ManagedBy = "terraform"
    Module    = "networking/route53"
  }
  tags = merge(local.default_tags, var.tags)

  create_zone        = var.create_zone
  create_public_zone = var.create_zone && !var.private_zone

  zone_id = var.create_zone ? (
    var.private_zone ? aws_route53_zone.private[0].zone_id : aws_route53_zone.public[0].zone_id
  ) : var.zone_id
}
