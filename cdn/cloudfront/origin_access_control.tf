locals {
  s3_origins = var.create_origin_access_control ? {
    for o in var.origins : o.origin_id => o if o.s3_origin
  } : {}
}

resource "aws_cloudfront_origin_access_control" "this" {
  for_each = local.s3_origins

  name                              = "${var.name}-${each.key}"
  description                       = "OAC for ${each.key}"
  origin_access_control_origin_type = var.origin_access_control_origin_type
  signing_behavior                  = var.origin_access_control_signing_behavior
  signing_protocol                  = var.origin_access_control_signing_protocol
}
