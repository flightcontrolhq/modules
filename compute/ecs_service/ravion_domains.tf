################################################################################
# Ravion-managed service domain (opt-in)
################################################################################
# When var.cluster_parent_domain_id is set, this module always declares an
# auto-allocated FQDN child of the cluster (Mode A — rides the cluster
# wildcard via SNI). When var.domains is non-empty, it additionally
# declares a Mode B `ravion_domain` carrying its own cert that covers
# only the customer FQDNs.
#
# Both live side-by-side: the listener rule matches BOTH the auto-FQDN
# AND every customer FQDN. This gives the customer a no-downtime window
# to flip their DNS over — until then, traffic to the auto-FQDN keeps
# working. Once the customer's DNS records resolve (MATCHED in the
# Domains tab), the Ravion control plane retires the auto-FQDN
# (`MaybeRetireAutoDomain` deletes the Route53 record + soft-deletes
# the allocation). The listener rule keeps both entries — the orphaned
# auto-FQDN match is harmless because no DNS resolves to it anymore.
#
# Wire the parent ecs_cluster module's Ravion outputs:
#   module "service" {
#     source                     = ".../compute/ecs_service"
#     cluster_parent_domain_id   = module.cluster.ravion_cluster_domain_id
#     cluster_https_listener_arn = module.cluster.public_alb_https_listener_arn
#     cluster_alb_dns_name       = module.cluster.public_alb_dns_name   # Mode B only
#     cluster_alb_zone_id        = module.cluster.public_alb_zone_id    # Mode B only
#     ravion_aws_account_id      = module.cluster.ravion_aws_account_id # Mode B only
#     ravion_aws_region          = module.cluster.ravion_aws_region     # Mode B only
#     domains                    = ["api.example.com"]                  # opts into Mode B
#   }

locals {
  ravion_managed      = var.cluster_parent_domain_id != null && var.cluster_parent_domain_id != ""
  ravion_has_listener = var.cluster_https_listener_arn != null && var.cluster_https_listener_arn != ""
  ravion_mode_b       = local.ravion_managed && length(var.domains) > 0

  # Listener rule matches BOTH the auto-FQDN AND each customer FQDN so
  # the auto-FQDN keeps working until the customer's DNS is verified.
  ravion_host_header_values = concat(
    local.ravion_managed ? [ravion_domain.auto[0].fqdn] : [],
    local.ravion_mode_b ? var.domains : [],
  )

  ravion_target_group_arn = local.enable_load_balancer && var.deployment_type == "rolling" ? (
    length(aws_lb_target_group.this) > 0 ? aws_lb_target_group.this[0].arn : null
    ) : (
    length(aws_lb_target_group.tg_1) > 0 ? aws_lb_target_group.tg_1[0].arn : null
  )
}

# Mode A — always allocated when the cluster domain is wired. Rides the
# cluster wildcard cert via SNI; no new ACM cert.
resource "ravion_domain" "auto" {
  count = local.ravion_managed ? 1 : 0

  name      = var.name
  parent_id = var.cluster_parent_domain_id
}

# Mode B — additional resource that issues a service cert covering only
# var.domains. Independent of the Mode A auto-FQDN.
resource "ravion_domain" "custom" {
  count = local.ravion_mode_b ? 1 : 0

  name      = "${var.name}-custom"
  parent_id = var.cluster_parent_domain_id

  target = {
    dns_name = var.cluster_alb_dns_name
    zone_id  = var.cluster_alb_zone_id
  }

  certificate = {
    aws_account_id = var.ravion_aws_account_id
    aws_region     = coalesce(var.ravion_aws_region, local.region)
    domains        = var.domains
  }

  lifecycle {
    precondition {
      condition     = var.cluster_alb_dns_name != null && var.cluster_alb_dns_name != "" && var.cluster_alb_zone_id != null && var.cluster_alb_zone_id != ""
      error_message = "Setting `domains` (Mode B) requires cluster_alb_dns_name + cluster_alb_zone_id (pipe module.cluster.public_alb_dns_name + module.cluster.public_alb_zone_id)."
    }
    precondition {
      condition     = var.ravion_aws_account_id != null && var.ravion_aws_account_id != ""
      error_message = "Setting `domains` (Mode B) requires ravion_aws_account_id (pipe module.cluster.ravion_aws_account_id)."
    }
  }
}

# Mode B only: attach the service cert as SNI extra on the cluster listener.
resource "aws_lb_listener_certificate" "ravion" {
  count = local.ravion_mode_b && local.ravion_has_listener ? 1 : 0

  listener_arn    = var.cluster_https_listener_arn
  certificate_arn = ravion_domain.custom[0].cert_arn
}

resource "aws_lb_listener_rule" "ravion" {
  count = local.ravion_managed && local.ravion_has_listener ? 1 : 0

  listener_arn = var.cluster_https_listener_arn
  priority     = var.ravion_listener_rule_priority

  condition {
    host_header {
      values = local.ravion_host_header_values
    }
  }

  action {
    type             = "forward"
    target_group_arn = local.ravion_target_group_arn
  }

  tags = merge(local.tags, {
    Name = "${var.name}-ravion"
  })
}
