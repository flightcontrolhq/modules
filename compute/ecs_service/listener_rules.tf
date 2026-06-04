################################################################################
# ALB Listener Rules
#
# Rules initially forward to the production target group (tg-1). During
# native traffic-shift deployments (blue_green/linear/canary) the ECS
# deployment controller rewrites the rule's forward action between tg-1
# and tg-2 via the infrastructure role, hence ignore_changes on action.
################################################################################

resource "aws_lb_listener_rule" "alb" {
  for_each = local.enable_load_balancer ? {
    for idx, rule in var.load_balancer_attachment.listener_rules : idx => rule
  } : {}

  listener_arn = each.value.listener_arn
  priority     = each.value.priority

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg_1[0].arn
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
    for_each = [for c in each.value.conditions : c if c.type == "http-request-method"]
    content {
      http_request_method {
        values = condition.value.values
      }
    }
  }

  dynamic "condition" {
    for_each = [for c in each.value.conditions : c if c.type == "query-string"]
    content {
      query_string {
        key   = try(condition.value.values[0], null)
        value = try(condition.value.values[1], condition.value.values[0])
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

  # The ECS deployment controller rewrites the forward action during
  # native traffic-shift deployments; a no-op for rolling deployments.
  lifecycle {
    ignore_changes = [action]
  }
}

################################################################################
# NLB Listeners
# For NLB, we create the listener directly (no listener rules in NLB).
# The ECS deployment controller rewrites the default action during
# native traffic-shift deployments.
################################################################################

resource "aws_lb_listener" "nlb" {
  count = local.enable_load_balancer && local.enable_nlb_listener ? 1 : 0

  load_balancer_arn = var.load_balancer_attachment.nlb_listener.nlb_arn
  port              = var.load_balancer_attachment.nlb_listener.port
  protocol          = var.load_balancer_attachment.nlb_listener.protocol

  # TLS-specific settings
  certificate_arn = var.load_balancer_attachment.nlb_listener.protocol == "TLS" ? var.load_balancer_attachment.nlb_listener.certificate_arn : null
  ssl_policy      = var.load_balancer_attachment.nlb_listener.protocol == "TLS" ? var.load_balancer_attachment.nlb_listener.ssl_policy : null
  alpn_policy     = var.load_balancer_attachment.nlb_listener.protocol == "TLS" ? var.load_balancer_attachment.nlb_listener.alpn_policy : null

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg_1[0].arn
  }

  tags = merge(local.tags, {
    Name = "${var.name}-nlb-listener"
  })

  # The ECS deployment controller rewrites the default action during
  # native traffic-shift deployments; a no-op for rolling deployments.
  lifecycle {
    ignore_changes = [default_action]
  }
}
