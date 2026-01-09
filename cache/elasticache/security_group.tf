################################################################################
# Security Group
################################################################################

resource "aws_security_group" "this" {
  count = local.create_security_group ? 1 : 0

  name        = "${var.name}-elasticache"
  description = "Security group for ${var.name} ElastiCache cluster"
  vpc_id      = var.vpc_id

  tags = merge(local.tags, {
    Name = "${var.name}-elasticache"
  })

  lifecycle {
    create_before_destroy = true
  }
}

################################################################################
# Ingress Rules - Security Groups
################################################################################

resource "aws_security_group_rule" "ingress_security_groups" {
  for_each = local.create_security_group ? toset(var.allowed_security_group_ids) : toset([])

  type                     = "ingress"
  from_port                = local.port
  to_port                  = local.port
  protocol                 = "tcp"
  source_security_group_id = each.value
  security_group_id        = aws_security_group.this[0].id
  description              = "Allow ${var.engine} traffic from ${each.value}"
}

################################################################################
# Ingress Rules - CIDR Blocks
################################################################################

resource "aws_security_group_rule" "ingress_cidr_blocks" {
  count = local.create_security_group && length(var.allowed_cidr_blocks) > 0 ? 1 : 0

  type              = "ingress"
  from_port         = local.port
  to_port           = local.port
  protocol          = "tcp"
  cidr_blocks       = var.allowed_cidr_blocks
  security_group_id = aws_security_group.this[0].id
  description       = "Allow ${var.engine} traffic from CIDR blocks"
}

################################################################################
# Egress Rule
################################################################################

resource "aws_security_group_rule" "egress" {
  count = local.create_security_group ? 1 : 0

  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  ipv6_cidr_blocks  = ["::/0"]
  security_group_id = aws_security_group.this[0].id
  description       = "Allow all outbound traffic"
}
