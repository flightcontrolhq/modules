resource "aws_cloudfront_vpc_origin" "this" {
  for_each = { for o in var.origins : o.origin_id => o if o.vpc_origin_enabled }

  vpc_origin_endpoint_config {
    name                   = "${var.name}-${each.key}"
    arn                    = each.value.vpc_origin_arn
    http_port              = each.value.http_port
    https_port             = each.value.https_port
    origin_protocol_policy = each.value.origin_protocol_policy

    origin_ssl_protocols {
      items    = each.value.origin_ssl_protocols
      quantity = length(each.value.origin_ssl_protocols)
    }
  }

  tags = merge(local.tags, { Name = "${var.name}-${each.key}" })

  # Order distribution detachment before deleting the VPC origin.
  lifecycle {
    create_before_destroy = true
  }
}
