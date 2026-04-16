################################################################################
# Security Group
################################################################################

module "security_group" {
  source = "../security-groups"

  name        = var.name
  name_suffix = "nlb"
  description = "Security group for ${var.name} NLB"
  vpc_id      = var.vpc_id
  tags        = var.tags

  allow_all_egress = true

  ingress_rules = concat(
    # Per-port IPv4 ingress rules
    flatten([
      for listener in var.listener_ports : [
        for cidr in var.ingress_cidr_blocks : {
          description = "Allow ${upper(listener.protocol)} traffic on port ${listener.port} from ${cidr}"
          from_port   = listener.port
          to_port     = listener.port
          ip_protocol = lower(listener.protocol) == "udp" ? "udp" : "tcp"
          cidr_ipv4   = cidr
        }
      ]
    ]),
    # Per-port IPv6 ingress rules
    flatten([
      for listener in var.listener_ports : [
        for cidr in var.ingress_ipv6_cidr_blocks : {
          description = "Allow ${upper(listener.protocol)} traffic on port ${listener.port} from ${cidr}"
          from_port   = listener.port
          to_port     = listener.port
          ip_protocol = lower(listener.protocol) == "udp" ? "udp" : "tcp"
          cidr_ipv6   = cidr
        }
      ]
    ])
  )
}
