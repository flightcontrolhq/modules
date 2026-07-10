################################################################################
# Security Groups
################################################################################

# Clients attach this security group to gain NFS access to the mount targets.
# It carries no ingress rules of its own; the mount-target security group
# references it as an allowed source.
module "client_security_group" {
  source = "../../networking/security-groups"

  name        = var.name
  name_suffix = "efs-client"
  description = "Client security group granting NFS access to the ${var.name} EFS file system"
  vpc_id      = var.vpc_id
  tags        = var.tags

  ingress_rules = []

  # Egress to VPC only. For ip_protocol="-1" (all protocols), AWS requires
  # from_port/to_port to be -1; setting them to 0 causes update failures.
  egress_rules = [
    {
      description = "Allow outbound traffic within VPC"
      from_port   = -1
      to_port     = -1
      ip_protocol = "-1"
      cidr_ipv4   = data.aws_vpc.this.cidr_block
    }
  ]
}

module "security_group" {
  source = "../../networking/security-groups"

  name        = var.name
  name_suffix = "efs"
  description = "Mount target security group for ${var.name} EFS file system"
  vpc_id      = var.vpc_id
  tags        = var.tags

  ingress_rules = concat(
    # Managed client security group
    [
      {
        description                  = "Allow NFS traffic from the EFS client security group"
        from_port                    = 2049
        to_port                      = 2049
        ip_protocol                  = "tcp"
        referenced_security_group_id = module.client_security_group.security_group_id
      }
    ],
    # Security group sources
    [
      for sg_id in var.allowed_security_group_ids : {
        description                  = "Allow NFS traffic from ${sg_id}"
        from_port                    = 2049
        to_port                      = 2049
        ip_protocol                  = "tcp"
        referenced_security_group_id = sg_id
      }
    ],
    # IPv4 CIDR sources
    [
      for cidr in var.allowed_cidr_blocks : {
        description = "Allow NFS traffic from ${cidr}"
        from_port   = 2049
        to_port     = 2049
        ip_protocol = "tcp"
        cidr_ipv4   = cidr
      }
    ],
    # IPv6 CIDR sources
    [
      for cidr in var.allowed_ipv6_cidr_blocks : {
        description = "Allow NFS traffic from ${cidr}"
        from_port   = 2049
        to_port     = 2049
        ip_protocol = "tcp"
        cidr_ipv6   = cidr
      }
    ]
  )

  # Egress to VPC only. For ip_protocol="-1" (all protocols), AWS requires
  # from_port/to_port to be -1; setting them to 0 causes update failures.
  egress_rules = [
    {
      description = "Allow outbound traffic within VPC"
      from_port   = -1
      to_port     = -1
      ip_protocol = "-1"
      cidr_ipv4   = data.aws_vpc.this.cidr_block
    }
  ]
}
