################################################################################
# Ingress NLB
#
# One TLS listener on 443 fronting the host ingress proxy, which routes
# `<sandboxId>-<port>.sbx.<env>.<domain>` to the right tap IP in process. Hosts
# are registered into the target group by the reconciler when they turn ready
# and deregistered when they are cordoned — never by Terraform.
################################################################################

resource "aws_lb" "this" {
  name               = local.name_prefix
  load_balancer_type = "network"
  internal           = !local.internet_facing
  subnets            = local.nlb_subnet_ids
  security_groups    = [aws_security_group.nlb.id]
  ip_address_type    = local.ip_address_type

  enable_cross_zone_load_balancing = true

  tags = merge(local.tags, { Name = local.name_prefix })
}

# Instance targets: the host ingress proxy. TCP, not TLS — the listener
# terminates TLS with the wildcard cert and the proxy sees plain HTTP with the
# client IP preserved by the NLB.
resource "aws_lb_target_group" "proxy" {
  name        = "${local.name_prefix}-tg"
  port        = var.proxy_port
  protocol    = "TCP"
  target_type = "instance"
  vpc_id      = var.execution_environment.vpc_id

  deregistration_delay = 30

  health_check {
    protocol            = "TCP"
    interval            = 10
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = merge(local.tags, { Name = "${local.name_prefix}-tg" })

  lifecycle {
    create_before_destroy = true
  }
}

# IP targets: individual sandbox IPs, for raw TCP exposure in vpc-ip mode
# (`<ip>:3306` reachable with stock tools). Tower registers `<sandbox ip>:<port>`
# and adds the matching listener; the group exists so it has somewhere to put
# them.
resource "aws_lb_target_group" "tcp" {
  count = var.enable_tcp_exposure ? 1 : 0

  name        = "${local.name_prefix}-ip"
  port        = 443
  protocol    = "TCP"
  target_type = "ip"
  vpc_id      = var.execution_environment.vpc_id

  deregistration_delay = 10

  health_check {
    protocol            = "TCP"
    interval            = 10
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = merge(local.tags, { Name = "${local.name_prefix}-ip" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "TLS"
  ssl_policy        = var.ssl_policy
  certificate_arn   = var.wait_for_certificate_validation ? aws_acm_certificate_validation.wildcard[0].certificate_arn : aws_acm_certificate.wildcard.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.proxy.arn
  }

  tags = merge(local.tags, { Name = "${local.name_prefix}-https" })
}
