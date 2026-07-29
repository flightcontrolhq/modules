################################################################################
# Target Group and Listener Rules
#
# One instance target group. In-place deploys keep serving from it: the
# deploy script drains each instance, swaps the app, and re-registers.
################################################################################

resource "aws_lb_target_group" "app" {
  count = local.load_balancer_creation_enabled ? 1 : 0

  name        = "${substr(var.name, 0, min(length(var.name), 28))}-tg"
  port        = var.load_balancer_attachment.target_group.port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "instance"

  deregistration_delay = var.load_balancer_attachment.target_group.deregistration_delay
  slow_start           = var.load_balancer_attachment.target_group.slow_start

  health_check {
    enabled             = var.load_balancer_attachment.target_group.health_check.enabled
    path                = var.load_balancer_attachment.target_group.health_check.path
    port                = var.load_balancer_attachment.target_group.health_check.port
    protocol            = "HTTP"
    matcher             = var.load_balancer_attachment.target_group.health_check.matcher
    interval            = var.load_balancer_attachment.target_group.health_check.interval
    timeout             = var.load_balancer_attachment.target_group.health_check.timeout
    healthy_threshold   = var.load_balancer_attachment.target_group.health_check.healthy_threshold
    unhealthy_threshold = var.load_balancer_attachment.target_group.health_check.unhealthy_threshold
  }

  dynamic "stickiness" {
    for_each = var.load_balancer_attachment.target_group.stickiness != null ? [var.load_balancer_attachment.target_group.stickiness] : []
    content {
      enabled         = stickiness.value.enabled
      type            = stickiness.value.type
      cookie_duration = stickiness.value.cookie_duration
      cookie_name     = stickiness.value.cookie_name
    }
  }

  tags = merge(local.tags, {
    Name = "${var.name}-tg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb_listener_rule" "app" {
  for_each = local.load_balancer_creation_enabled ? {
    for idx, rule in var.load_balancer_attachment.listener_rules : idx => rule
  } : {}

  listener_arn = each.value.listener_arn
  priority     = each.value.priority

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app[0].arn
  }

  dynamic "condition" {
    for_each = [for c in each.value.conditions : c if c.type == "path-pattern"]
    content {
      path_pattern {
        values = condition.value.values
      }
    }
  }

  dynamic "condition" {
    for_each = [for c in each.value.conditions : c if c.type == "host-header"]
    content {
      host_header {
        values = condition.value.values
      }
    }
  }

  dynamic "condition" {
    for_each = [for c in each.value.conditions : c if c.type == "http-header"]
    content {
      http_header {
        http_header_name = condition.value.values[0]
        values           = slice(condition.value.values, 1, length(condition.value.values))
      }
    }
  }

  dynamic "condition" {
    for_each = [for c in each.value.conditions : c if c.type == "source-ip"]
    content {
      source_ip {
        values = condition.value.values
      }
    }
  }

  tags = merge(local.tags, {
    Name = "${var.name}-rule-${each.key}"
  })
}
