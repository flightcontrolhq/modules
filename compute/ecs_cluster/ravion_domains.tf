################################################################################
# Ravion-managed cluster domain (opt-in)
################################################################################
# When var.use_ravion_managed_domains = true, Ravion issues a wildcard cert
# `*.<name>-<hash>.<ravion-apex>` (+ apex) and this module owns the public ALB
# HTTPS listener with that cert as its default. Services pass the outputs
# (ravion_cluster_domain_fqdn, public_alb_https_listener_arn, ...) to
# ecs_service to nest their domains under the wildcard.
#
# The listener lives here (not in the alb submodule) to avoid a DAG cycle:
# aws_lb.this -> ravion_certificate.cluster (targets the ALB) ->
# aws_lb_listener.ravion_https (uses the cert). ravion_certificate with
# role=shared_wildcard blocks until ISSUED, so cert_arn is valid at listener
# create time.

locals {
  enable_ravion_domain = var.use_ravion_managed_domains && var.enable_public_alb
}

resource "ravion_certificate" "cluster" {
  count = local.enable_ravion_domain ? 1 : 0

  role           = "shared_wildcard"
  wildcard       = true
  name           = coalesce(var.ravion_cluster_name, var.name)
  aws_account_id = var.ravion_aws_account_id
  aws_region     = coalesce(var.ravion_aws_region, local.region)

  lifecycle {
    precondition {
      condition     = !var.use_ravion_managed_domains || var.enable_public_alb
      error_message = "use_ravion_managed_domains requires enable_public_alb = true."
    }
    precondition {
      condition     = !var.use_ravion_managed_domains || (var.ravion_aws_account_id != null && var.ravion_aws_account_id != "")
      error_message = "ravion_aws_account_id (aws_*) is required when use_ravion_managed_domains = true."
    }
  }
}

resource "aws_lb_listener" "ravion_https" {
  count = local.enable_ravion_domain && var.public_alb_enable_https ? 1 : 0

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

# The alb submodule only opens port 443 when it owns the HTTPS listener; in
# Ravion mode it does not, so open it here (mirrors the submodule's rules).
resource "aws_vpc_security_group_ingress_rule" "ravion_https_ipv4" {
  for_each = local.enable_ravion_domain && var.public_alb_enable_https ? toset(var.public_alb_ingress_cidr_blocks) : toset([])

  security_group_id = module.public_alb[0].security_group_id
  description       = "Allow HTTPS from ${each.value} (Ravion-owned listener)"
  cidr_ipv4         = each.value
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  tags              = var.tags
}

resource "aws_vpc_security_group_ingress_rule" "ravion_https_ipv6" {
  for_each = local.enable_ravion_domain && var.public_alb_enable_https ? toset(["::/0"]) : toset([])

  security_group_id = module.public_alb[0].security_group_id
  description       = "Allow HTTPS from ${each.value} (Ravion-owned listener)"
  cidr_ipv6         = each.value
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  tags              = var.tags
}
