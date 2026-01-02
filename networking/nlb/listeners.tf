################################################################################
# Target Groups
################################################################################

resource "aws_lb_target_group" "this" {
  for_each = var.target_groups

  name        = "${var.name}-${each.key}"
  port        = each.value.port
  protocol    = each.value.protocol
  vpc_id      = var.vpc_id
  target_type = each.value.target_type

  deregistration_delay   = each.value.deregistration_delay
  preserve_client_ip     = each.value.protocol != "TLS" ? each.value.preserve_client_ip : null
  proxy_protocol_v2      = each.value.proxy_protocol_v2
  connection_termination = each.value.connection_termination

  health_check {
    enabled             = each.value.health_check.enabled
    healthy_threshold   = each.value.health_check.healthy_threshold
    unhealthy_threshold = each.value.health_check.unhealthy_threshold
    interval            = each.value.health_check.interval
    port                = each.value.health_check.port
    protocol            = each.value.health_check.protocol
    path                = each.value.health_check.protocol != "TCP" ? each.value.health_check.path : null
    matcher             = each.value.health_check.protocol != "TCP" ? each.value.health_check.matcher : null
    timeout             = each.value.health_check.timeout
  }

  tags = merge(local.tags, {
    Name = "${var.name}-${each.key}"
  })

  lifecycle {
    create_before_destroy = true
  }
}

################################################################################
# Listeners
################################################################################

resource "aws_lb_listener" "this" {
  for_each = var.listeners

  load_balancer_arn = aws_lb.this.arn
  port              = each.value.port
  protocol          = each.value.protocol

  # TLS-specific settings
  certificate_arn = each.value.protocol == "TLS" ? each.value.certificate_arn : null
  ssl_policy      = each.value.protocol == "TLS" ? each.value.ssl_policy : null
  alpn_policy     = each.value.protocol == "TLS" ? each.value.alpn_policy : null

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this[each.value.target_group_key].arn
  }

  tags = merge(local.tags, {
    Name = "${var.name}-${each.key}"
  })
}

################################################################################
# Additional Certificates (SNI)
################################################################################

resource "aws_lb_listener_certificate" "additional" {
  for_each = { for cert in local.additional_certificates : "${cert.listener_key}-${cert.certificate_arn}" => cert }

  listener_arn    = aws_lb_listener.this[each.value.listener_key].arn
  certificate_arn = each.value.certificate_arn
}
