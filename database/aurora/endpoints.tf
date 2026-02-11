################################################################################
# Custom Endpoints
################################################################################

resource "aws_rds_cluster_endpoint" "this" {
  for_each = var.custom_endpoints

  cluster_identifier          = aws_rds_cluster.this.id
  cluster_endpoint_identifier = "${var.name}-${each.key}"
  custom_endpoint_type        = each.value.type

  static_members   = each.value.static_members
  excluded_members = each.value.excluded_members

  tags = merge(local.tags, {
    Name = "${var.name}-${each.key}"
  }, each.value.tags != null ? each.value.tags : {})

  lifecycle {
    precondition {
      condition     = contains(["READER", "ANY"], each.value.type)
      error_message = "Custom endpoint type must be one of: READER, ANY. Got: ${each.value.type}"
    }

    precondition {
      condition     = each.value.static_members == null || each.value.excluded_members == null
      error_message = "Cannot specify both static_members and excluded_members for custom endpoint '${each.key}'."
    }
  }
}
