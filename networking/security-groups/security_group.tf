################################################################################
# Local Values
################################################################################

locals {
  # Tags
  default_tags = {
    ManagedBy = "terraform"
    Module    = "networking/security-groups"
  }
  tags = merge(local.default_tags, var.tags)

  # Full security group name
  security_group_name = "${var.name}-${var.name_suffix}"

  # Create a unique key for each ingress rule to use with for_each
  # Using index-based keys to avoid unknown values at plan time (e.g., referenced_security_group_id)
  ingress_rules_map = {
    for idx, rule in var.ingress_rules : tostring(idx) => rule
  }

  # Create a unique key for each egress rule to use with for_each
  # Using index-based keys to avoid unknown values at plan time (e.g., referenced_security_group_id)
  egress_rules_map = {
    for idx, rule in var.egress_rules : tostring(idx) => rule
  }
}

################################################################################
# Security Group
################################################################################

resource "aws_security_group" "this" {
  name        = local.security_group_name
  description = var.description
  vpc_id      = var.vpc_id

  tags = merge(local.tags, {
    Name = local.security_group_name
  })

  lifecycle {
    create_before_destroy = true
  }
}

################################################################################
# Ingress Rules
################################################################################

resource "aws_vpc_security_group_ingress_rule" "this" {
  for_each = local.ingress_rules_map

  security_group_id = aws_security_group.this.id
  description       = each.value.description

  from_port   = each.value.from_port
  to_port     = each.value.to_port
  ip_protocol = each.value.ip_protocol

  # Source types - only one will be set
  cidr_ipv4                    = each.value.cidr_ipv4
  cidr_ipv6                    = each.value.cidr_ipv6
  referenced_security_group_id = each.value.self ? aws_security_group.this.id : each.value.referenced_security_group_id
  prefix_list_id               = each.value.prefix_list_id

  tags = merge(local.tags, {
    Name = "${local.security_group_name}-ingress"
  })
}

################################################################################
# Egress Rules
################################################################################

resource "aws_vpc_security_group_egress_rule" "this" {
  for_each = local.egress_rules_map

  security_group_id = aws_security_group.this.id
  description       = each.value.description

  from_port   = each.value.from_port
  to_port     = each.value.to_port
  ip_protocol = each.value.ip_protocol

  # Destination types - only one will be set
  cidr_ipv4                    = each.value.cidr_ipv4
  cidr_ipv6                    = each.value.cidr_ipv6
  referenced_security_group_id = each.value.self ? aws_security_group.this.id : each.value.referenced_security_group_id
  prefix_list_id               = each.value.prefix_list_id

  tags = merge(local.tags, {
    Name = "${local.security_group_name}-egress"
  })
}

################################################################################
# Default Egress Rules (Allow All)
################################################################################

resource "aws_vpc_security_group_egress_rule" "allow_all_ipv4" {
  count = var.allow_all_egress ? 1 : 0

  security_group_id = aws_security_group.this.id
  description       = "Allow all outbound IPv4 traffic"

  ip_protocol = "-1"
  cidr_ipv4   = "0.0.0.0/0"

  tags = merge(local.tags, {
    Name = "${local.security_group_name}-egress-all-ipv4"
  })
}

resource "aws_vpc_security_group_egress_rule" "allow_all_ipv6" {
  count = var.allow_all_egress && !var.allow_all_egress_ipv4_only ? 1 : 0

  security_group_id = aws_security_group.this.id
  description       = "Allow all outbound IPv6 traffic"

  ip_protocol = "-1"
  cidr_ipv6   = "::/0"

  tags = merge(local.tags, {
    Name = "${local.security_group_name}-egress-all-ipv6"
  })
}
