################################################################################
# Ravion-managed cluster domain (opt-in)
################################################################################
# When var.use_ravion_managed_domains = true, Ravion issues ONE wildcard cert
# `*.<name>-<hash>.<ravion-apex>` (+ apex) and this module owns the cluster ALB
# HTTPS listener(s) with that cert as the default. The same cert backs BOTH the
# public and the private ALB listener (an ACM cert ARN can default many
# listeners), so public AND private services nest their domains under the one
# wildcard. Services pass the matching outputs to ecs_service:
#   - public service  -> public_alb_https_listener_arn  + public_alb_dns_name/zone
#   - private service  -> private_alb_https_listener_arn + private_alb_dns_name/zone
#
# The listeners live here (not in the alb submodule) to avoid a DAG cycle:
# aws_lb.this -> ravion_certificate.cluster -> aws_lb_listener.ravion_https*
# (uses the cert). ravion_certificate with role=shared_wildcard blocks until
# ISSUED, so cert_arn is valid at listener create time.

locals {
  enable_ravion_domain           = var.use_ravion_managed_domains && (var.enable_public_alb || var.enable_private_alb)
  enable_ravion_public_listener  = local.enable_ravion_domain && var.enable_public_alb && var.public_alb_enable_https
  enable_ravion_private_listener = local.enable_ravion_domain && var.enable_private_alb && var.private_alb_enable_https
}

resource "ravion_certificate" "cluster" {
  count = local.enable_ravion_domain ? 1 : 0

  role           = "shared_wildcard"
  wildcard       = true
  name           = coalesce(var.ravion_cluster_name, var.module_instance_given_id, var.name)
  aws_account_id = var.ravion_aws_account_id
  aws_region     = coalesce(var.ravion_aws_region, local.region)

  # Ravion publishes a *.<apex> ALIAS to this ALB so service auto-FQDNs
  # (<svc>.<apex>) resolve under the cluster wildcard. Public ALB if present,
  # else private. (A single wildcard record serves one ALB; mixed public+private
  # clusters route to the public one.)
  target_dns_name = var.enable_public_alb ? module.public_alb[0].alb_dns_name : (var.enable_private_alb ? module.private_alb[0].alb_dns_name : null)
  target_zone_id  = var.enable_public_alb ? module.public_alb[0].alb_zone_id : (var.enable_private_alb ? module.private_alb[0].alb_zone_id : null)

  lifecycle {
    precondition {
      condition     = !var.use_ravion_managed_domains || var.enable_public_alb || var.enable_private_alb
      error_message = "use_ravion_managed_domains requires at least one ALB (enable_public_alb or enable_private_alb)."
    }
    precondition {
      condition     = !var.use_ravion_managed_domains || (var.ravion_aws_account_id != null && var.ravion_aws_account_id != "")
      error_message = "ravion_aws_account_id (aws_*) is required when use_ravion_managed_domains = true."
    }
  }
}

# Public ALB Ravion listener.
resource "aws_lb_listener" "ravion_https" {
  count = local.enable_ravion_public_listener ? 1 : 0

  load_balancer_arn = module.public_alb[0].alb_arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = var.public_alb_ssl_policy
  certificate_arn   = ravion_certificate.cluster[0].cert_arn

  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "Not found"
      status_code  = "404"
    }
  }

  tags = merge(var.tags, { Name = "${var.name}-pub-https" })
}

# Private ALB Ravion listener (same wildcard cert as the public one).
resource "aws_lb_listener" "ravion_https_private" {
  count = local.enable_ravion_private_listener ? 1 : 0

  load_balancer_arn = module.private_alb[0].alb_arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = var.private_alb_ssl_policy
  certificate_arn   = ravion_certificate.cluster[0].cert_arn

  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "Not found"
      status_code  = "404"
    }
  }

  tags = merge(var.tags, { Name = "${var.name}-priv-https" })
}

# The alb submodule only opens port 443 when it owns the HTTPS listener; in
# Ravion mode it does not, so open it here (mirrors the submodule's rules).
resource "aws_vpc_security_group_ingress_rule" "ravion_https_ipv4" {
  for_each = local.enable_ravion_public_listener ? toset(var.public_alb_ingress_cidr_blocks) : toset([])

  security_group_id = module.public_alb[0].security_group_id
  description       = "Allow HTTPS from ${each.value} (Ravion-owned listener)"
  cidr_ipv4         = each.value
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  tags              = var.tags
}

resource "aws_vpc_security_group_ingress_rule" "ravion_https_ipv6" {
  for_each = local.enable_ravion_public_listener ? toset(["::/0"]) : toset([])

  security_group_id = module.public_alb[0].security_group_id
  description       = "Allow HTTPS from ${each.value} (Ravion-owned listener)"
  cidr_ipv6         = each.value
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  tags              = var.tags
}

# Private ALB 443 ingress (mirrors the public rules for the private listener).
resource "aws_vpc_security_group_ingress_rule" "ravion_https_private_ipv4" {
  for_each = local.enable_ravion_private_listener ? toset(var.private_alb_ingress_cidr_blocks) : toset([])

  security_group_id = module.private_alb[0].security_group_id
  description       = "Allow HTTPS from ${each.value} (Ravion-owned listener)"
  cidr_ipv4         = each.value
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  tags              = var.tags
}
