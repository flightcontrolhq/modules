################################################################################
# ECS Service Security Group
################################################################################

module "security_group" {
  source = "../../networking/security-groups"

  name        = var.name
  name_suffix = "ecs-service"
  description = "Security group for ECS service ${var.name}"
  vpc_id      = var.vpc_id
  tags        = var.tags

  all_egress_enabled = true

  ingress_rules = concat(
    # Load balancer ingress (from LB security group if provided, else VPC CIDR)
    local.enable_load_balancer ? [
      var.load_balancer_security_group_id != null ? {
        description                  = "Allow traffic from load balancer on port ${local.lb_container_port}"
        from_port                    = local.lb_container_port
        to_port                      = local.lb_container_port
        ip_protocol                  = "tcp"
        referenced_security_group_id = var.load_balancer_security_group_id
        } : {
        description = "Allow traffic from load balancer on port ${local.lb_container_port}"
        from_port   = local.lb_container_port
        to_port     = local.lb_container_port
        ip_protocol = "tcp"
        cidr_ipv4   = data.aws_vpc.this.cidr_block
      }
    ] : [],
    # Additional CIDR blocks
    [
      for cidr in var.allowed_cidr_blocks : {
        description = "Allow traffic from ${cidr}"
        from_port   = local.lb_container_port != null ? local.lb_container_port : 0
        to_port     = local.lb_container_port != null ? local.lb_container_port : 65535
        ip_protocol = "tcp"
        cidr_ipv4   = cidr
      }
    ]
  )
}

locals {
  nlb_listener_ingress_protocol = (
    local.enable_nlb_listener && lower(var.load_balancer_attachment.nlb_listener.protocol) == "udp" ? "udp" : "tcp"
  )
}

resource "aws_vpc_security_group_ingress_rule" "nlb_listener_ipv4" {
  for_each = local.enable_nlb_listener && var.load_balancer_security_group_id != null ? toset(var.load_balancer_ingress_cidr_blocks) : toset([])

  security_group_id = var.load_balancer_security_group_id
  description       = "Allow ${upper(var.load_balancer_attachment.nlb_listener.protocol)} traffic on port ${var.load_balancer_attachment.nlb_listener.port} from ${each.value}"
  from_port         = var.load_balancer_attachment.nlb_listener.port
  to_port           = var.load_balancer_attachment.nlb_listener.port
  ip_protocol       = local.nlb_listener_ingress_protocol
  cidr_ipv4         = each.value
}

resource "aws_vpc_security_group_ingress_rule" "nlb_listener_ipv6" {
  for_each = local.enable_nlb_listener && var.load_balancer_security_group_id != null ? toset(var.load_balancer_ingress_ipv6_cidr_blocks) : toset([])

  security_group_id = var.load_balancer_security_group_id
  description       = "Allow ${upper(var.load_balancer_attachment.nlb_listener.protocol)} traffic on port ${var.load_balancer_attachment.nlb_listener.port} from ${each.value}"
  from_port         = var.load_balancer_attachment.nlb_listener.port
  to_port           = var.load_balancer_attachment.nlb_listener.port
  ip_protocol       = local.nlb_listener_ingress_protocol
  cidr_ipv6         = each.value
}
