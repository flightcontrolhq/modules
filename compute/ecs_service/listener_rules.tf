################################################################################
# ALB Listener Rules
# For blue/green deployments, an external controller manages target group switching
################################################################################

resource "aws_lb_listener_rule" "alb" {
  # When Ravion is managing the cluster's HTTPS listener (cluster_parent_domain_id
  # is set), the `aws_lb_listener_rule.ravion` resource owns ALB routing for this
  # service — scoped by host_header to the service's auto-FQDN + custom domains.
  # Caller-supplied listener_rules from the control plane are redundant in that
  # mode and actively harmful: they collide on priorities across services on the
  # shared listener, and any path-only rule catches traffic destined for sibling
  # services. We short-circuit them entirely.
  for_each = local.enable_load_balancer && !local.ravion_managed ? {
    for idx, rule in local.load_balancer_attachment.listener_rules : idx => rule
  } : {}

  listener_arn = each.value.listener_arn
  priority     = each.value.priority

  action {
    type = "forward"
    target_group_arn = (
      var.deployment_type == "blue_green"
      ? aws_lb_target_group.tg_1[0].arn
      : aws_lb_target_group.this[0].arn
    )
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

  # Ignore changes to action as the external deployment controller manages target group switching for blue/green
  # This is a no-op for rolling deployments (nothing external modifies the action)
  lifecycle {
    ignore_changes = [action]
  }
}

################################################################################
# NLB Listeners
# For NLB, we create the listener directly (no listener rules in NLB)
# For blue/green deployments, an external controller manages target group switching
################################################################################

resource "aws_lb_listener" "nlb" {
  count = local.enable_load_balancer && local.enable_nlb_listener ? 1 : 0

  load_balancer_arn = local.load_balancer_attachment.nlb_listener.nlb_arn
  port              = local.load_balancer_attachment.nlb_listener.port
  protocol          = local.load_balancer_attachment.nlb_listener.protocol

  # TLS-specific settings
  certificate_arn = local.load_balancer_attachment.nlb_listener.protocol == "TLS" ? local.load_balancer_attachment.nlb_listener.certificate_arn : null
  ssl_policy      = local.load_balancer_attachment.nlb_listener.protocol == "TLS" ? local.load_balancer_attachment.nlb_listener.ssl_policy : null
  alpn_policy     = local.load_balancer_attachment.nlb_listener.protocol == "TLS" ? local.load_balancer_attachment.nlb_listener.alpn_policy : null

  default_action {
    type = "forward"
    target_group_arn = (
      var.deployment_type == "blue_green"
      ? aws_lb_target_group.tg_1[0].arn
      : aws_lb_target_group.this[0].arn
    )
  }

  tags = merge(local.tags, {
    Name = "${var.name}-nlb-listener"
  })

  # Ignore changes to default_action as the external deployment controller manages target group switching for blue/green
  # This is a no-op for rolling deployments (nothing external modifies the action)
  lifecycle {
    ignore_changes = [default_action]
  }
}
