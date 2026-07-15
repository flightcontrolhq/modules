################################################################################
# Security Group for Service Instances
################################################################################

module "instance_security_group" {
  source = "../../networking/security-groups"

  name        = var.name
  name_suffix = "instance"
  description = "Security group for ${var.name} EC2 service instances"
  vpc_id      = var.vpc_id
  tags        = var.tags

  all_egress_enabled = true

  ingress_rules = concat(
    # Allow the load balancer to reach the app port
    local.enable_load_balancer && var.load_balancer_security_group_id != null && var.app_port != null ? [
      {
        description                  = "Allow inbound from load balancer"
        from_port                    = var.app_port
        to_port                      = var.app_port
        ip_protocol                  = "tcp"
        referenced_security_group_id = var.load_balancer_security_group_id
      }
    ] : [],
    # Additional direct sources
    var.app_port != null ? [
      for cidr in var.allowed_cidr_blocks : {
        description = "Allow inbound from ${cidr}"
        from_port   = var.app_port
        to_port     = var.app_port
        ip_protocol = "tcp"
        cidr_ipv4   = cidr
      }
    ] : []
  )
}
