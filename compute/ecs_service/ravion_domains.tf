################################################################################
# Ravion-managed service domain (opt-in)
################################################################################
# When var.cluster_parent_domain_id is set, this module declares a
# `ravion_domain` resource. Two modes are auto-selected by whether
# `var.domains` is empty:
#
#   - **Mode A** (`var.domains = []`) — default. Allocates
#     `<service-name>-<hash>.<cluster-fqdn>` and rides the cluster's
#     wildcard cert via SNI. No new ACM cert. The host_header rule
#     matches the auto-allocated FQDN.
#
#   - **Mode B** (`var.domains = ["api.example.com", ...]`) — service
#     gets ITS OWN cert covering only `var.domains`. NO auto-FQDN is
#     allocated (the service is exposed exclusively at the customer's
#     own FQDNs). The host_header rule matches every domain in the
#     list. The new cert is attached to the cluster's HTTPS listener as
#     an SNI extra (`aws_lb_listener_certificate.ravion`).
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

  # In Mode A the host_header matches the auto-allocated FQDN. In Mode B
  # it matches every customer-owned FQDN.
  ravion_host_header_values = local.ravion_managed ? (
    local.ravion_mode_b ? var.domains : [ravion_domain.this[0].fqdn]
  ) : []

  ravion_target_group_arn = local.enable_load_balancer && var.deployment_type == "rolling" ? (
    length(aws_lb_target_group.this) > 0 ? aws_lb_target_group.this[0].arn : null
    ) : (
    length(aws_lb_target_group.tg_1) > 0 ? aws_lb_target_group.tg_1[0].arn : null
  )
}

resource "ravion_domain" "this" {
  count = local.ravion_managed ? 1 : 0

  name      = var.name
  parent_id = var.cluster_parent_domain_id

  # Mode B: provide target + certificate so the API issues a service cert
  # covering only var.domains (no auto-FQDN).
  target = local.ravion_mode_b ? {
    dns_name = var.cluster_alb_dns_name
    zone_id  = var.cluster_alb_zone_id
  } : null

  certificate = local.ravion_mode_b ? {
    aws_account_id = var.ravion_aws_account_id
    aws_region     = coalesce(var.ravion_aws_region, local.region)
    domains        = var.domains
  } : null

  lifecycle {
    precondition {
      condition     = !local.ravion_mode_b || (var.cluster_alb_dns_name != null && var.cluster_alb_dns_name != "" && var.cluster_alb_zone_id != null && var.cluster_alb_zone_id != "")
      error_message = "Setting `domains` (Mode B) requires cluster_alb_dns_name + cluster_alb_zone_id (pipe module.cluster.public_alb_dns_name + module.cluster.public_alb_zone_id)."
    }
    precondition {
      condition     = !local.ravion_mode_b || (var.ravion_aws_account_id != null && var.ravion_aws_account_id != "")
      error_message = "Setting `domains` (Mode B) requires ravion_aws_account_id (pipe module.cluster.ravion_aws_account_id)."
    }
  }
}

# Mode B only: attach the service cert as SNI extra on the cluster listener.
resource "aws_lb_listener_certificate" "ravion" {
  count = local.ravion_mode_b && local.ravion_has_listener ? 1 : 0

  listener_arn    = var.cluster_https_listener_arn
  certificate_arn = ravion_domain.this[0].cert_arn
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
