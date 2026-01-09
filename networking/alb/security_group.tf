################################################################################
# Security Group
################################################################################

module "security_group" {
  source = "../security-groups"

  name        = var.name
  name_suffix = "alb"
  description = "Security group for ${var.name} ALB"
  vpc_id      = var.vpc_id
  tags        = var.tags

  allow_all_egress = true

  ingress_rules = concat(
    # HTTP ingress (IPv4)
    local.create_http_listener ? [
      for cidr in var.ingress_cidr_blocks : {
        description = "Allow HTTP traffic from ${cidr}"
        from_port   = var.http_listener_port
        to_port     = var.http_listener_port
        ip_protocol = "tcp"
        cidr_ipv4   = cidr
      }
    ] : [],
    # HTTP ingress (IPv6)
    local.create_http_listener ? [
      for cidr in var.ingress_ipv6_cidr_blocks : {
        description = "Allow HTTP traffic from ${cidr}"
        from_port   = var.http_listener_port
        to_port     = var.http_listener_port
        ip_protocol = "tcp"
        cidr_ipv6   = cidr
      }
    ] : [],
    # HTTPS ingress (IPv4)
    local.create_https_listener ? [
      for cidr in var.ingress_cidr_blocks : {
        description = "Allow HTTPS traffic from ${cidr}"
        from_port   = var.https_listener_port
        to_port     = var.https_listener_port
        ip_protocol = "tcp"
        cidr_ipv4   = cidr
      }
    ] : [],
    # HTTPS ingress (IPv6)
    local.create_https_listener ? [
      for cidr in var.ingress_ipv6_cidr_blocks : {
        description = "Allow HTTPS traffic from ${cidr}"
        from_port   = var.https_listener_port
        to_port     = var.https_listener_port
        ip_protocol = "tcp"
        cidr_ipv6   = cidr
      }
    ] : []
  )
}
