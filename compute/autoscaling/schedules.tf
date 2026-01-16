################################################################################
# Scheduled Scaling Actions
################################################################################

resource "aws_autoscaling_schedule" "this" {
  for_each = { for schedule in var.schedules : schedule.name => schedule }

  scheduled_action_name  = each.value.name
  autoscaling_group_name = aws_autoscaling_group.this.name

  # Capacity settings (all optional, at least one should be set)
  min_size         = each.value.min_size
  max_size         = each.value.max_size
  desired_capacity = each.value.desired_capacity

  # Scheduling options
  start_time = each.value.start_time
  end_time   = each.value.end_time
  recurrence = each.value.recurrence
  time_zone  = each.value.time_zone
}
