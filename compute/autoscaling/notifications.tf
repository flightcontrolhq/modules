################################################################################
# Auto Scaling Group Notifications
################################################################################

resource "aws_autoscaling_notification" "this" {
  count = local.enable_notifications ? 1 : 0

  group_names = [aws_autoscaling_group.this.name]

  notifications = var.notifications.notifications

  topic_arn = var.notifications.topic_arn
}
