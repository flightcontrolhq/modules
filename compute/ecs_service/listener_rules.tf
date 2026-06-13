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
  # The mirrored rule (index 0) takes the module-managed base priority when
  # the green test rule is enabled so the test rule can sit one slot ahead;
  # every other rule keeps its configured priority.
  priority = (
    local.green_alb_listener_rule_enabled && each.key == "0"
    ? local.green_production_priority
    : each.value.priority
  )

  # When the target groups have target-level stickiness the forward
  # action must carry group-level stickiness or ELBv2 rejects the
  # weighted forward ECS writes during traffic-shift deployments — see
  # alb_group_stickiness_enabled in locals.tf.
  action {
    type             = "forward"
    target_group_arn = local.alb_group_stickiness_enabled ? null : aws_lb_target_group.tg_1[0].arn

    dynamic "forward" {
      for_each = local.alb_group_stickiness_enabled ? [1] : []
      content {
        target_group {
          arn = aws_lb_target_group.tg_1[0].arn
        }
        stickiness {
          enabled  = true
          duration = local.alb_group_stickiness_duration
        }
      }
    }
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
# ALB Test (Green) Listener Rule
#
# Dedicated rule, created by default for ALB services, that routes test
# traffic to the alternate (green) target group (tg-2) during native
# traffic-shift deployments. It reuses the production listener and
# routing conditions (listener_rules[0]) but forwards to the green target
# group; the ECS deployment controller rewrites its forward action through
# the TEST_TRAFFIC_SHIFT lifecycle stages so the green revision can be
# validated before production traffic shifts, hence ignore_changes on
# action. Outside a deployment tg-2 is empty, so it returns no targets until
# a deployment registers the green revision.
################################################################################

resource "aws_lb_listener_rule" "test" {
  count = local.green_alb_listener_rule_enabled ? 1 : 0

  listener_arn = var.load_balancer_attachment.listener_rules[0].listener_arn
  # One slot ahead of the production rule so a request carrying the test
  # header matches this rule first; ALB routes by priority order, not by
  # specificity, so without this it would fall through to production.
  priority = local.green_test_priority

  # Same group-stickiness requirement as the production rule: ECS
  # rewrites this rule's forward action through the TEST_TRAFFIC_SHIFT
  # stages, and ELBv2 rejects the rewrite when the sticky target groups
  # are referenced without group-level stickiness on the action.
  action {
    type             = "forward"
    target_group_arn = local.alb_group_stickiness_enabled ? null : aws_lb_target_group.tg_2[0].arn

    dynamic "forward" {
      for_each = local.alb_group_stickiness_enabled ? [1] : []
      content {
        target_group {
          arn = aws_lb_target_group.tg_2[0].arn
        }
        stickiness {
          enabled  = true
          duration = local.alb_group_stickiness_duration
        }
      }
    }
  }

  # Distinguishing condition: only requests carrying the test header reach
  # the green target group. Combined with the mirrored production
  # conditions below, normal (header-less) traffic still matches production.
  condition {
    http_header {
      http_header_name = var.test_header_name
      values           = [var.test_header_value]
    }
  }

  dynamic "condition" {
    for_each = [for c in var.load_balancer_attachment.listener_rules[0].conditions : c if c.type == "path-pattern"]
    content {
      path_pattern {
        values = condition.value.values
      }
    }
  }

  dynamic "condition" {
    for_each = [for c in var.load_balancer_attachment.listener_rules[0].conditions : c if c.type == "host-header"]
    content {
      host_header {
        values = condition.value.values
      }
    }
  }

  dynamic "condition" {
    for_each = [for c in var.load_balancer_attachment.listener_rules[0].conditions : c if c.type == "http-header"]
    content {
      http_header {
        http_header_name = condition.value.values[0]
        values           = slice(condition.value.values, 1, length(condition.value.values))
      }
    }
  }

  dynamic "condition" {
    for_each = [for c in var.load_balancer_attachment.listener_rules[0].conditions : c if c.type == "http-request-method"]
    content {
      http_request_method {
        values = condition.value.values
      }
    }
  }

  dynamic "condition" {
    for_each = [for c in var.load_balancer_attachment.listener_rules[0].conditions : c if c.type == "query-string"]
    content {
      query_string {
        key   = try(condition.value.values[0], null)
        value = try(condition.value.values[1], condition.value.values[0])
      }
    }
  }

  dynamic "condition" {
    for_each = [for c in var.load_balancer_attachment.listener_rules[0].conditions : c if c.type == "source-ip"]
    content {
      source_ip {
        values = condition.value.values
      }
    }
  }

  tags = merge(local.tags, {
    Name = "${var.name}-test-rule"
  })

  # The ECS deployment controller rewrites the forward action during
  # native traffic-shift deployments (TEST_TRAFFIC_SHIFT stages).
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
