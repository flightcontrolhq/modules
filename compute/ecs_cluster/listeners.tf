################################################################################
# Cluster ALB HTTPS listeners
################################################################################
# ecs_cluster ALWAYS owns the cluster ALB HTTPS listener(s) (the alb submodule
# never creates them — see load_balancers.tf) so that toggling
# var.use_ravion_managed_domains is an IN-PLACE certificate swap on a stable TF
# address rather than a destroy+create across two addresses. Only the default
# certificate SOURCE changes by mode:
#
#   - use_ravion_managed_domains = true  -> the Ravion wildcard cert
#     (ravion_aws_acm_certificate.cluster, see ravion_domains.tf) is the default cert on
#     BOTH listeners; public/private services nest their auto-FQDNs under it.
#   - use_ravion_managed_domains = false -> the listener uses the customer's
#     first public/private_alb_certificate_arns entry as default and attaches
#     the rest for SNI.
#
# The listeners live here (not in the alb submodule) to avoid a DAG cycle:
# aws_lb.this -> ravion_aws_acm_certificate.cluster -> aws_lb_listener.public_https
# (uses the cert). ravion_aws_acm_certificate with role=shared_wildcard blocks until
# ISSUED, so cert_arn is valid at listener create time.

# Public ALB HTTPS listener. Mode-independent address: created whenever the
# public ALB has HTTPS enabled.
resource "aws_lb_listener" "public_https" {
  count = var.enable_public_alb && var.public_alb_enable_https ? 1 : 0

  load_balancer_arn = module.public_alb[0].alb_arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = var.public_alb_ssl_policy
  # try(...) defers to the precondition below for the clean error when BYO mode
  # has no cert ARN, instead of a cryptic index-out-of-range.
  certificate_arn = local.enable_ravion_domain ? ravion_aws_acm_certificate.cluster[0].arn : try(var.public_alb_certificate_arns[0], null)

  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "Not found"
      status_code  = "404"
    }
  }

  lifecycle {
    precondition {
      condition     = local.enable_ravion_domain || length(var.public_alb_certificate_arns) >= 1
      error_message = "public_alb_certificate_arns must include at least one ACM certificate ARN when public_alb_enable_https = true and use_ravion_managed_domains = false."
    }
  }

  tags = merge(local.tags, { Name = "${var.name}-pub-https" })
}

# Customer SNI certs for the public listener (BYO mode only; the Ravion wildcard
# needs no extra SNI certs). Gated on the listener existing so the slice is
# never evaluated when HTTPS / the ALB is off (mirrors the alb submodule's
# `additional` idiom and avoids slice([], 1, 0) on the default config).
resource "aws_lb_listener_certificate" "public_sni" {
  # length > 1 keeps slice() self-safe (never slice([], 1, 0)) independent of the
  # listener precondition: only the 2nd+ ARNs become SNI certs.
  for_each = (var.enable_public_alb && var.public_alb_enable_https && !local.enable_ravion_domain && length(var.public_alb_certificate_arns) > 1) ? toset(slice(var.public_alb_certificate_arns, 1, length(var.public_alb_certificate_arns))) : toset([])

  listener_arn    = aws_lb_listener.public_https[0].arn
  certificate_arn = each.value
}

# Private ALB HTTPS listener (same Ravion wildcard cert as the public one in
# managed mode; the customer's first private cert ARN otherwise).
resource "aws_lb_listener" "private_https" {
  count = var.enable_private_alb && var.private_alb_enable_https ? 1 : 0

  load_balancer_arn = module.private_alb[0].alb_arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = var.private_alb_ssl_policy
  certificate_arn   = local.enable_ravion_domain ? ravion_aws_acm_certificate.cluster[0].arn : try(var.private_alb_certificate_arns[0], null)

  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "Not found"
      status_code  = "404"
    }
  }

  lifecycle {
    precondition {
      condition     = local.enable_ravion_domain || length(var.private_alb_certificate_arns) >= 1
      error_message = "private_alb_certificate_arns must include at least one ACM certificate ARN when private_alb_enable_https = true and use_ravion_managed_domains = false."
    }
  }

  tags = merge(local.tags, { Name = "${var.name}-priv-https" })
}

# Customer SNI certs for the private listener (BYO mode only).
resource "aws_lb_listener_certificate" "private_sni" {
  for_each = (var.enable_private_alb && var.private_alb_enable_https && !local.enable_ravion_domain && length(var.private_alb_certificate_arns) > 1) ? toset(slice(var.private_alb_certificate_arns, 1, length(var.private_alb_certificate_arns))) : toset([])

  listener_arn    = aws_lb_listener.private_https[0].arn
  certificate_arn = each.value
}

################################################################################
# 443 ingress
################################################################################
# The alb submodule only opens 443 when it owns the HTTPS listener; it no longer
# does, so ecs_cluster opens 443 here in BOTH modes (mirrors the submodule's
# rules). Mode-independent so toggling use_ravion_managed_domains never churns
# the SG rules.
resource "aws_vpc_security_group_ingress_rule" "public_https_ipv4" {
  for_each = var.enable_public_alb && var.public_alb_enable_https ? toset(var.public_alb_ingress_cidr_blocks) : toset([])

  security_group_id = module.public_alb[0].security_group_id
  description       = "Allow HTTPS from ${each.value}"
  cidr_ipv4         = each.value
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  tags              = local.tags
}

resource "aws_vpc_security_group_ingress_rule" "public_https_ipv6" {
  for_each = var.enable_public_alb && var.public_alb_enable_https ? toset(["::/0"]) : toset([])

  security_group_id = module.public_alb[0].security_group_id
  description       = "Allow HTTPS from ${each.value}"
  cidr_ipv6         = each.value
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  tags              = local.tags
}

# Private ALB 443 ingress (mirrors the public rules for the private listener).
resource "aws_vpc_security_group_ingress_rule" "private_https_ipv4" {
  for_each = var.enable_private_alb && var.private_alb_enable_https ? toset(var.private_alb_ingress_cidr_blocks) : toset([])

  security_group_id = module.private_alb[0].security_group_id
  description       = "Allow HTTPS from ${each.value}"
  cidr_ipv4         = each.value
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  tags              = local.tags
}

resource "aws_vpc_security_group_ingress_rule" "private_https_ipv6" {
  for_each = var.enable_private_alb && var.private_alb_enable_https ? toset(["::/0"]) : toset([])

  security_group_id = module.private_alb[0].security_group_id
  description       = "Allow HTTPS from ${each.value}"
  cidr_ipv6         = each.value
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  tags              = local.tags
}

################################################################################
# State moves
################################################################################
# Renames within ecs_cluster (clusters already in Ravion mode keep their state):
moved {
  from = aws_lb_listener.ravion_https
  to   = aws_lb_listener.public_https
}

moved {
  from = aws_lb_listener.ravion_https_private
  to   = aws_lb_listener.private_https
}

moved {
  from = aws_vpc_security_group_ingress_rule.ravion_https_ipv4
  to   = aws_vpc_security_group_ingress_rule.public_https_ipv4
}

moved {
  from = aws_vpc_security_group_ingress_rule.ravion_https_ipv6
  to   = aws_vpc_security_group_ingress_rule.public_https_ipv6
}

moved {
  from = aws_vpc_security_group_ingress_rule.ravion_https_private_ipv4
  to   = aws_vpc_security_group_ingress_rule.private_https_ipv4
}

# BYO clusters with existing state had their HTTPS listener inside the alb
# submodule; refactoring it out to the root is expressed with a cross-module
# moved block (supported "refactor out of a module" pattern). The submodule's
# 443 SG ingress rules came from a for_each in the security-groups module and
# cannot be moved this way — those are a one-time destroy+create on the BYO
# migration (acceptable: nothing is in prod yet).
moved {
  from = module.public_alb[0].aws_lb_listener.https[0]
  to   = aws_lb_listener.public_https[0]
}

moved {
  from = module.private_alb[0].aws_lb_listener.https[0]
  to   = aws_lb_listener.private_https[0]
}
