################################################################################
# ECS Service Security Group
################################################################################

resource "aws_security_group" "this" {
  name        = "${var.name}-ecs-service"
  description = "Security group for ECS service ${var.name}"
  vpc_id      = var.vpc_id

  tags = merge(local.tags, {
    Name = "${var.name}-ecs-service"
  })

  lifecycle {
    create_before_destroy = true
  }
}

################################################################################
# Egress Rules
################################################################################

resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.this.id
  description       = "Allow all outbound traffic"

  ip_protocol = "-1"
  cidr_ipv4   = "0.0.0.0/0"

  tags = merge(local.tags, {
    Name = "${var.name}-all-egress"
  })
}

################################################################################
# Ingress Rules - Load Balancer
################################################################################

# Get the load balancer security group from the target group ARN (if available)
# This requires the ALB security group to be passed in or derived

resource "aws_vpc_security_group_ingress_rule" "lb" {
  for_each = local.enable_load_balancer ? toset([tostring(local.lb_container_port)]) : toset([])

  security_group_id = aws_security_group.this.id
  description       = "Allow traffic from load balancer on port ${each.value}"

  from_port   = tonumber(each.value)
  to_port     = tonumber(each.value)
  ip_protocol = "tcp"

  # Allow from VPC CIDR for load balancer traffic
  # In production, you'd typically reference the LB security group directly
  cidr_ipv4 = data.aws_vpc.this.cidr_block

  tags = merge(local.tags, {
    Name = "${var.name}-lb-ingress-${each.value}"
  })
}

################################################################################
# Ingress Rules - Additional CIDR Blocks
################################################################################

resource "aws_vpc_security_group_ingress_rule" "cidr" {
  for_each = toset(var.allowed_cidr_blocks)

  security_group_id = aws_security_group.this.id
  description       = "Allow traffic from ${each.value}"

  from_port   = local.lb_container_port != null ? local.lb_container_port : 0
  to_port     = local.lb_container_port != null ? local.lb_container_port : 65535
  ip_protocol = "tcp"
  cidr_ipv4   = each.value

  tags = merge(local.tags, {
    Name = "${var.name}-cidr-ingress"
  })
}

################################################################################
# Data Source for VPC CIDR
################################################################################

data "aws_vpc" "this" {
  id = var.vpc_id
}


