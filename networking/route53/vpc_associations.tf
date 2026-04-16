################################################################################
# Private Zone VPC Associations
#
# Additional VPC associations for an existing private hosted zone.
# When create_zone = true, the initial VPCs are attached on the aws_route53_zone
# resource; any subsequent associations should be managed via this resource to
# allow cross-account / cross-region flexibility and to avoid drift.
################################################################################

resource "aws_route53_zone_association" "this" {
  for_each = var.create_zone ? {} : {
    for k, v in var.vpc_associations : k => v
  }

  zone_id    = local.zone_id
  vpc_id     = each.value.vpc_id
  vpc_region = each.value.vpc_region
}
