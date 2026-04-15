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

  allow_all_egress = true

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
