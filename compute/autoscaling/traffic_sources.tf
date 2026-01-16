################################################################################
# Auto Scaling Group Traffic Source Attachments
################################################################################

resource "aws_autoscaling_traffic_source_attachment" "this" {
  for_each = { for idx, ts in var.traffic_sources : "${ts.type}-${idx}" => ts }

  autoscaling_group_name = aws_autoscaling_group.this.name

  traffic_source {
    identifier = each.value.identifier
    type       = each.value.type
  }
}
