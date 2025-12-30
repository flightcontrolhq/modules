################################################################################
# Security Group
################################################################################

resource "aws_security_group" "this" {
  name        = "${var.name}-alb"
  description = "Security group for ${var.name} ALB"
  vpc_id      = var.vpc_id

  tags = merge(local.tags, {
    Name = "${var.name}-alb"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group_rule" "ingress_http" {
  count = local.create_http_listener ? 1 : 0

  type              = "ingress"
  from_port         = var.http_listener_port
  to_port           = var.http_listener_port
  protocol          = "tcp"
  cidr_blocks       = var.ingress_cidr_blocks
  ipv6_cidr_blocks  = var.ingress_ipv6_cidr_blocks
  security_group_id = aws_security_group.this.id
  description       = "Allow HTTP traffic"
}

resource "aws_security_group_rule" "ingress_https" {
  count = local.create_https_listener ? 1 : 0

  type              = "ingress"
  from_port         = var.https_listener_port
  to_port           = var.https_listener_port
  protocol          = "tcp"
  cidr_blocks       = var.ingress_cidr_blocks
  ipv6_cidr_blocks  = var.ingress_ipv6_cidr_blocks
  security_group_id = aws_security_group.this.id
  description       = "Allow HTTPS traffic"
}

resource "aws_security_group_rule" "egress" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  ipv6_cidr_blocks  = ["::/0"]
  security_group_id = aws_security_group.this.id
  description       = "Allow all outbound traffic"
}

