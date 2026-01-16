################################################################################
# Lifecycle Hooks
################################################################################

resource "aws_autoscaling_lifecycle_hook" "this" {
  for_each = { for hook in var.lifecycle_hooks : hook.name => hook }

  name                    = each.value.name
  autoscaling_group_name  = aws_autoscaling_group.this.name
  lifecycle_transition    = each.value.lifecycle_transition
  default_result          = each.value.default_result
  heartbeat_timeout       = each.value.heartbeat_timeout
  notification_metadata   = each.value.notification_metadata
  notification_target_arn = each.value.notification_target_arn
  role_arn                = each.value.role_arn
}
