locals {
  s3_origin_enableds = var.origin_access_control_creation_enabled ? {
    for o in var.origins : o.origin_id => o if o.s3_origin_enabled
  } : {}
}

resource "aws_cloudfront_origin_access_control" "this" {
  for_each = local.s3_origin_enableds

  # Order distribution detachment before deleting the access control.
  lifecycle {
    create_before_destroy = true
  }

  name                              = "${var.name}-${each.key}"
  description                       = "OAC for ${each.key}"
  origin_access_control_origin_type = var.origin_access_control_origin_type
  signing_behavior                  = var.origin_access_control_signing_behavior
  signing_protocol                  = var.origin_access_control_signing_protocol
}
