################################################################################
# Host security group
#
# The only security group a host carries. The pool is a tenant of a Ravion
# network module, which publishes subnets rather than a workload SG, so this
# group states the whole envelope on its own. In vpc-ip mode the sandbox IPs are
# secondary addresses on the host ENI, so these rules govern sandbox traffic too
# — the per-sandbox policy (nftables, keyed by tap/IP) is enforced below this,
# on the host.
################################################################################

resource "aws_security_group" "host" {
  name        = "${local.name_prefix}-host"
  description = "Sandbox hosts for pool ${var.pool_id}"
  vpc_id      = var.vpc_id

  tags = merge(local.tags, { Name = "${local.name_prefix}-host" })

  lifecycle {
    create_before_destroy = true
  }
}

# --- ingress ----------------------------------------------------------------

resource "aws_vpc_security_group_ingress_rule" "host_proxy" {
  count = local.ingress_enabled ? 1 : 0

  security_group_id = aws_security_group.host.id
  description       = "Ingress proxy traffic from the NLB"

  referenced_security_group_id = aws_security_group.nlb[0].id
  ip_protocol                  = "tcp"
  from_port                    = var.proxy_port
  to_port                      = var.proxy_port

  tags = local.tags
}

# Arbitrary TCP exposure: the NLB's IP targets are sandbox IPs riding on host
# ENIs, so the host SG has to admit the whole envelope Tower may register in.
resource "aws_vpc_security_group_ingress_rule" "host_tcp_exposure" {
  count = local.tcp_exposure_enabled ? 1 : 0

  security_group_id = aws_security_group.host.id
  description       = "TCP exposure targets from the NLB"

  referenced_security_group_id = aws_security_group.nlb[0].id
  ip_protocol                  = "tcp"
  from_port                    = var.tcp_exposure_port_range.from
  to_port                      = var.tcp_exposure_port_range.to

  tags = local.tags
}

# Direct in-VPC reach to sandbox IPs (VPN, peered VPCs), which is the whole
# point of the private hosted zone in vpc-ip mode. Independent of ingress: on a
# pool with `ingress = null` this is the only way in, and the only way sandboxes
# are reached at all.
resource "aws_vpc_security_group_ingress_rule" "host_internal" {
  for_each = local.vpc_ip_mode ? toset(var.internal_access_cidrs) : toset([])

  security_group_id = aws_security_group.host.id
  description       = "Direct sandbox access from ${each.value}"

  cidr_ipv4   = each.value
  ip_protocol = "tcp"
  from_port   = 1
  to_port     = 65535

  tags = local.tags
}

# --- egress -----------------------------------------------------------------

resource "aws_vpc_security_group_egress_rule" "host_all" {
  for_each = var.host_allow_all_egress ? toset(var.host_egress_cidrs) : toset([])

  security_group_id = aws_security_group.host.id
  description       = "Unrestricted egress to ${each.value}"

  cidr_ipv4   = each.value
  ip_protocol = "-1"

  tags = local.tags
}

resource "aws_vpc_security_group_egress_rule" "host_ports" {
  for_each = var.host_allow_all_egress ? toset([]) : toset([
    for pair in setproduct(var.host_egress_cidrs, var.host_egress_ports) :
    "${pair[0]}|${pair[1]}"
  ])

  security_group_id = aws_security_group.host.id
  description       = "Egress tcp/${split("|", each.value)[1]} to ${split("|", each.value)[0]}"

  cidr_ipv4   = split("|", each.value)[0]
  ip_protocol = "tcp"
  from_port   = tonumber(split("|", each.value)[1])
  to_port     = tonumber(split("|", each.value)[1])

  tags = local.tags
}

# The sandbox-aware resolver answers guest DNS itself, but it has to ask
# something upstream first.
resource "aws_vpc_security_group_egress_rule" "host_dns_udp" {
  for_each = var.host_allow_all_egress ? toset([]) : toset(var.host_egress_cidrs)

  security_group_id = aws_security_group.host.id
  description       = "DNS (udp) to ${each.value}"

  cidr_ipv4   = each.value
  ip_protocol = "udp"
  from_port   = 53
  to_port     = 53

  tags = local.tags
}

resource "aws_vpc_security_group_egress_rule" "host_dns_tcp" {
  for_each = var.host_allow_all_egress ? toset([]) : toset(var.host_egress_cidrs)

  security_group_id = aws_security_group.host.id
  description       = "DNS (tcp) to ${each.value}"

  cidr_ipv4   = each.value
  ip_protocol = "tcp"
  from_port   = 53
  to_port     = 53

  tags = local.tags
}

resource "aws_vpc_security_group_egress_rule" "host_ipv6" {
  count = var.ipv6_enabled ? 1 : 0

  security_group_id = aws_security_group.host.id
  description       = "IPv6 egress"

  cidr_ipv6   = "::/0"
  ip_protocol = var.host_allow_all_egress ? "-1" : "tcp"
  from_port   = var.host_allow_all_egress ? null : 443
  to_port     = var.host_allow_all_egress ? null : 443

  tags = local.tags
}

################################################################################
# NLB security group
#
# Exists only alongside the NLB. With `ingress = null` neither this group nor
# any rule that references it is created — including the host group's rules
# above, which is why those are gated on the same switch.
################################################################################

resource "aws_security_group" "nlb" {
  count = local.ingress_enabled ? 1 : 0

  name        = "${local.name_prefix}-nlb"
  description = "Sandbox ingress NLB for pool ${var.pool_id}"
  vpc_id      = var.vpc_id

  tags = merge(local.tags, { Name = "${local.name_prefix}-nlb" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "nlb_https" {
  for_each = toset(local.ingress_cidrs)

  security_group_id = aws_security_group.nlb[0].id
  description       = "HTTPS from ${each.value}"

  cidr_ipv4   = each.value
  ip_protocol = "tcp"
  from_port   = 443
  to_port     = 443

  tags = local.tags
}

resource "aws_vpc_security_group_ingress_rule" "nlb_https_ipv6" {
  count = local.ingress_enabled && var.ipv6_enabled ? 1 : 0

  security_group_id = aws_security_group.nlb[0].id
  description       = "HTTPS over IPv6"

  cidr_ipv6   = "::/0"
  ip_protocol = "tcp"
  from_port   = 443
  to_port     = 443

  tags = local.tags
}

resource "aws_vpc_security_group_ingress_rule" "nlb_tcp_exposure" {
  for_each = local.tcp_exposure_enabled ? toset(local.ingress_cidrs) : toset([])

  security_group_id = aws_security_group.nlb[0].id
  description       = "TCP exposure ports from ${each.value}"

  cidr_ipv4   = each.value
  ip_protocol = "tcp"
  from_port   = var.tcp_exposure_port_range.from
  to_port     = var.tcp_exposure_port_range.to

  tags = local.tags
}

resource "aws_vpc_security_group_egress_rule" "nlb_to_hosts" {
  count = local.ingress_enabled ? 1 : 0

  security_group_id = aws_security_group.nlb[0].id
  description       = "Forward to sandbox hosts"

  referenced_security_group_id = aws_security_group.host.id
  ip_protocol                  = "tcp"
  from_port                    = 1
  to_port                      = 65535

  tags = local.tags
}

