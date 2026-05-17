################################################################################
# Target Groups - Rolling Deployment
################################################################################

resource "aws_lb_target_group" "this" {
  count = local.enable_load_balancer && var.deployment_type == "rolling" ? 1 : 0

  name        = "${substr(var.name, 0, min(length(var.name), 28))}-tg"
  port        = local.load_balancer_attachment.target_group.port
  protocol    = local.load_balancer_attachment.target_group.protocol
  vpc_id      = var.vpc_id
  target_type = local.load_balancer_attachment.target_group.target_type

  deregistration_delay = local.load_balancer_attachment.target_group.deregistration_delay
  slow_start           = contains(["HTTP", "HTTPS"], local.load_balancer_attachment.target_group.protocol) ? local.load_balancer_attachment.target_group.slow_start : null

  health_check {
    enabled             = local.load_balancer_attachment.target_group.health_check.enabled
    path                = contains(["HTTP", "HTTPS"], local.load_balancer_attachment.target_group.protocol) ? local.load_balancer_attachment.target_group.health_check.path : null
    port                = local.load_balancer_attachment.target_group.health_check.port
    protocol            = coalesce(local.load_balancer_attachment.target_group.health_check.protocol, local.load_balancer_attachment.target_group.protocol)
    matcher             = contains(["HTTP", "HTTPS"], local.load_balancer_attachment.target_group.protocol) ? local.load_balancer_attachment.target_group.health_check.matcher : null
    interval            = local.load_balancer_attachment.target_group.health_check.interval
    timeout             = local.load_balancer_attachment.target_group.health_check.timeout
    healthy_threshold   = local.load_balancer_attachment.target_group.health_check.healthy_threshold
    unhealthy_threshold = local.load_balancer_attachment.target_group.health_check.unhealthy_threshold
  }

  dynamic "stickiness" {
    for_each = local.load_balancer_attachment.target_group.stickiness != null ? [local.load_balancer_attachment.target_group.stickiness] : []
    content {
      enabled         = stickiness.value.enabled
      type            = stickiness.value.type
      cookie_duration = contains(["HTTP", "HTTPS"], local.load_balancer_attachment.target_group.protocol) ? stickiness.value.cookie_duration : null
      cookie_name     = contains(["HTTP", "HTTPS"], local.load_balancer_attachment.target_group.protocol) ? stickiness.value.cookie_name : null
    }
  }

  tags = merge(local.tags, {
    Name = "${var.name}-tg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

################################################################################
# Target Groups - Blue/Green Deployment
################################################################################

resource "aws_lb_target_group" "tg_1" {
  count = local.enable_load_balancer && var.deployment_type == "blue_green" ? 1 : 0

  name        = "${substr(var.name, 0, min(length(var.name), 24))}-tg-1"
  port        = local.load_balancer_attachment.target_group.port
  protocol    = local.load_balancer_attachment.target_group.protocol
  vpc_id      = var.vpc_id
  target_type = local.load_balancer_attachment.target_group.target_type

  deregistration_delay = local.load_balancer_attachment.target_group.deregistration_delay
  slow_start           = contains(["HTTP", "HTTPS"], local.load_balancer_attachment.target_group.protocol) ? local.load_balancer_attachment.target_group.slow_start : null

  health_check {
    enabled             = local.load_balancer_attachment.target_group.health_check.enabled
    path                = contains(["HTTP", "HTTPS"], local.load_balancer_attachment.target_group.protocol) ? local.load_balancer_attachment.target_group.health_check.path : null
    port                = local.load_balancer_attachment.target_group.health_check.port
    protocol            = coalesce(local.load_balancer_attachment.target_group.health_check.protocol, local.load_balancer_attachment.target_group.protocol)
    matcher             = contains(["HTTP", "HTTPS"], local.load_balancer_attachment.target_group.protocol) ? local.load_balancer_attachment.target_group.health_check.matcher : null
    interval            = local.load_balancer_attachment.target_group.health_check.interval
    timeout             = local.load_balancer_attachment.target_group.health_check.timeout
    healthy_threshold   = local.load_balancer_attachment.target_group.health_check.healthy_threshold
    unhealthy_threshold = local.load_balancer_attachment.target_group.health_check.unhealthy_threshold
  }

  dynamic "stickiness" {
    for_each = local.load_balancer_attachment.target_group.stickiness != null ? [local.load_balancer_attachment.target_group.stickiness] : []
    content {
      enabled         = stickiness.value.enabled
      type            = stickiness.value.type
      cookie_duration = contains(["HTTP", "HTTPS"], local.load_balancer_attachment.target_group.protocol) ? stickiness.value.cookie_duration : null
      cookie_name     = contains(["HTTP", "HTTPS"], local.load_balancer_attachment.target_group.protocol) ? stickiness.value.cookie_name : null
    }
  }

  tags = merge(local.tags, {
    Name           = "${var.name}-tg-1"
    DeploymentType = "tg-1"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb_target_group" "tg_2" {
  count = local.enable_load_balancer && var.deployment_type == "blue_green" ? 1 : 0

  name        = "${substr(var.name, 0, min(length(var.name), 24))}-tg-2"
  port        = local.load_balancer_attachment.target_group.port
  protocol    = local.load_balancer_attachment.target_group.protocol
  vpc_id      = var.vpc_id
  target_type = local.load_balancer_attachment.target_group.target_type

  deregistration_delay = local.load_balancer_attachment.target_group.deregistration_delay
  slow_start           = contains(["HTTP", "HTTPS"], local.load_balancer_attachment.target_group.protocol) ? local.load_balancer_attachment.target_group.slow_start : null

  health_check {
    enabled             = local.load_balancer_attachment.target_group.health_check.enabled
    path                = contains(["HTTP", "HTTPS"], local.load_balancer_attachment.target_group.protocol) ? local.load_balancer_attachment.target_group.health_check.path : null
    port                = local.load_balancer_attachment.target_group.health_check.port
    protocol            = coalesce(local.load_balancer_attachment.target_group.health_check.protocol, local.load_balancer_attachment.target_group.protocol)
    matcher             = contains(["HTTP", "HTTPS"], local.load_balancer_attachment.target_group.protocol) ? local.load_balancer_attachment.target_group.health_check.matcher : null
    interval            = local.load_balancer_attachment.target_group.health_check.interval
    timeout             = local.load_balancer_attachment.target_group.health_check.timeout
    healthy_threshold   = local.load_balancer_attachment.target_group.health_check.healthy_threshold
    unhealthy_threshold = local.load_balancer_attachment.target_group.health_check.unhealthy_threshold
  }

  dynamic "stickiness" {
    for_each = local.load_balancer_attachment.target_group.stickiness != null ? [local.load_balancer_attachment.target_group.stickiness] : []
    content {
      enabled         = stickiness.value.enabled
      type            = stickiness.value.type
      cookie_duration = contains(["HTTP", "HTTPS"], local.load_balancer_attachment.target_group.protocol) ? stickiness.value.cookie_duration : null
      cookie_name     = contains(["HTTP", "HTTPS"], local.load_balancer_attachment.target_group.protocol) ? stickiness.value.cookie_name : null
    }
  }

  tags = merge(local.tags, {
    Name           = "${var.name}-tg-2"
    DeploymentType = "tg-2"
  })

  lifecycle {
    create_before_destroy = true
  }
}

