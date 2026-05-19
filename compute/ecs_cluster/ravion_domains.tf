################################################################################
# Ravion-managed cluster domain (opt-in)
################################################################################
# When var.use_ravion_managed_domains is true, this module:
#
#   - allocates one `ravion_domain` for the cluster (root, no parent,
#     name = ravion_cluster_name or var.name; target = public ALB; wildcard
#     cert covering `*.<cluster-fqdn>` + `<cluster-fqdn>`),
#   - creates the public ALB's HTTPS listener directly here with the
#     freshly-issued wildcard cert as the listener's DEFAULT cert,
#   - SNI-attaches any customer-supplied `public_alb_certificate_arns`
#     as extras alongside the Ravion default.
#
# Why this module owns the listener instead of the alb module:
# AWS requires a default cert at listener-create time, and the Ravion-issued
# cert is what we want there. Feeding ravion_domain.cluster.cert_arn into
# `module.public_alb`'s `certificate_arns` input would form a cycle
# (ravion_domain.cluster.target uses the alb's dns_name output). By keeping
# the listener inside this module — where ravion_domain.cluster is already
# in scope as a resource — the planner sees a DAG instead of a cycle:
# aws_lb.this → ravion_domain.cluster → aws_lb_listener.ravion_https.
#
# Pass the outputs to each `ecs_service` instance:
#
#   module "service" {
#     source                     = ".../compute/ecs_service"
#     cluster_parent_domain_id   = module.cluster.ravion_cluster_domain_id
#     cluster_https_listener_arn = module.cluster.public_alb_https_listener_arn
#   }

resource "ravion_domain" "cluster" {
  count = local.enable_ravion_domain ? 1 : 0

  name = coalesce(var.ravion_cluster_name, var.name)

  target = {
    dns_name = module.public_alb[0].alb_dns_name
    zone_id  = module.public_alb[0].alb_zone_id
  }

  certificate = {
    aws_account_id = var.ravion_aws_account_id
    aws_region     = coalesce(var.ravion_aws_region, local.region)
    wildcard       = true
    # Custom domains live on per-service modules now — each service
    # declares them via ecs_service's `domains` input. Cluster cert
    # covers only the wildcard pair.
  }

  lifecycle {
    precondition {
      condition     = !var.use_ravion_managed_domains || var.enable_public_alb
      error_message = "use_ravion_managed_domains requires enable_public_alb = true (the cluster domain's DNS target is the public ALB)."
    }
    precondition {
      condition     = !var.use_ravion_managed_domains || (var.ravion_aws_account_id != null && var.ravion_aws_account_id != "")
      error_message = "ravion_aws_account_id is required when use_ravion_managed_domains = true (the Ravion AwsAccount row id the wildcard cert is issued in, e.g. 'aws_abc123')."
    }
  }
}

# HTTPS listener owned by this module when Ravion mode is on. The alb
# module skips creating its own (load_balancers.tf flips
# enable_https_listener off in that case).
resource "aws_lb_listener" "ravion_https" {
  count = local.enable_ravion_domain && var.public_alb_enable_https ? 1 : 0

  load_balancer_arn = module.public_alb[0].alb_arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = var.public_alb_ssl_policy
  certificate_arn   = ravion_domain.cluster[0].cert_arn

  # Mirrors the alb module's default action — fall through to a fixed
  # 404 when no per-service listener rule matches. Services attach
  # their own rules via aws_lb_listener_rule against this listener.
  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "Not found"
      status_code  = "404"
    }
  }

  tags = merge(local.tags, {
    Name = "${var.name}-pub-https"
  })
}

# When Ravion mode is on, the Ravion wildcard cert IS the listener's
# default cert. We intentionally do NOT SNI-attach the customer's
# `public_alb_certificate_arns` here — that input is a pre-Ravion
# concept (the cert ARN the customer pre-provisioned for the old
# alb-module listener), and the ARNs are frequently stale once the
# customer flips to Ravion mode. If you ever need additional certs
# bound to this listener, add them via a dedicated input on this
# module (not by piggybacking on public_alb_certificate_arns).

# Port 443 ingress on the public ALB's security group. The alb
# sub-module's security_group adds an HTTPS ingress rule ONLY when it
# owns the HTTPS listener (gated on its local.create_https_listener).
# With Ravion mode that flag is false (see load_balancers.tf), so
# without these resources packets to 443 reach the SG and get dropped
# before they ever touch the Ravion-owned listener — `dig` resolves,
# TLS connect times out. Mirrors the rules the alb module would have
# emitted: one per IPv4 cidr, one per IPv6 cidr.
resource "aws_vpc_security_group_ingress_rule" "ravion_https_ipv4" {
  for_each = local.enable_ravion_domain && var.public_alb_enable_https ? toset(var.public_alb_ingress_cidr_blocks) : toset([])

  security_group_id = module.public_alb[0].security_group_id
  description       = "Allow HTTPS traffic from ${each.value} (Ravion-owned listener)"
  cidr_ipv4         = each.value
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"

  tags = local.tags
}

resource "aws_vpc_security_group_ingress_rule" "ravion_https_ipv6" {
  for_each = local.enable_ravion_domain && var.public_alb_enable_https ? toset(["::/0"]) : toset([])

  security_group_id = module.public_alb[0].security_group_id
  description       = "Allow HTTPS traffic from ${each.value} (Ravion-owned listener)"
  cidr_ipv6         = each.value
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"

  tags = local.tags
}
