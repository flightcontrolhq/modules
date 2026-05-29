################################################################################
# Ravion-managed service domains
################################################################################
# Wired when cluster_parent_fqdn is set (piped from ecs_cluster). The `domains`
# list is the single source of truth — each entry is classified by whether the
# cluster wildcard cert covers it:
#
#   - wildcard-covered (<leaf>.<apex>, exactly one label under the cluster apex):
#     nests under the cluster wildcard cert via SNI. No per-service cert, and no
#     per-domain DNS record — the cluster's `*.<apex>` ALIAS already routes it.
#   - custom (anything else — external FQDNs, or names deeper than one label
#     under the apex the wildcard can't cover): covered by ONE per-service
#     instance ACM cert (<=10 SANs) attached to the cluster listener, plus a
#     routing record the customer adds.
#
# When `domains` is empty the service still gets an auto-FQDN
# `<given-id>.<apex>` (a wildcard-covered entry), so a service with no custom
# domains is reachable out of the box. The frontend pre-fills this same value
# into the domains list as the default; clearing it opts out.

locals {
  ravion_managed = var.cluster_parent_fqdn != null && var.cluster_parent_fqdn != ""
  apex           = local.ravion_managed ? var.cluster_parent_fqdn : ""

  # Auto-FQDN used when the domains list is empty (matches the frontend default).
  auto_fqdn = local.ravion_managed ? "${coalesce(var.module_instance_given_id, var.name)}.${local.apex}" : ""

  # The effective list: the user's domains, or the auto-FQDN when empty.
  effective_domains = local.ravion_managed ? (length(var.domains) > 0 ? var.domains : [local.auto_fqdn]) : []

  # Per-entry classification. wildcard-covered = "<leaf>.<apex>" with exactly one
  # label below the apex (the only shape the `*.<apex>` cert + ALIAS cover).
  wildcard_covered = [
    for d in local.effective_domains : d
    if endswith(d, ".${local.apex}") && !strcontains(trimsuffix(d, ".${local.apex}"), ".")
  ]
  custom_domains = [
    for d in local.effective_domains : d
    if !(endswith(d, ".${local.apex}") && !strcontains(trimsuffix(d, ".${local.apex}"), "."))
  ]

  # All of this service's hostnames route to its target group via one rule.
  ravion_host_headers = local.effective_domains

  ravion_priority = var.ravion_listener_rule_priority > 0 ? var.ravion_listener_rule_priority : ((parseint(substr(sha256(var.name), 0, 4), 16) % 49000) + 1000)

  ravion_target_group_arn = (
    length(aws_lb_target_group.this) > 0 ? aws_lb_target_group.this[0].arn : (
      length(aws_lb_target_group.tg_1) > 0 ? aws_lb_target_group.tg_1[0].arn : null
    )
  )
}

# Wildcard-covered domains (incl. the auto-FQDN): nest under the cluster
# wildcard. No per-service cert; the cluster `*.<apex>` ALIAS routes them.
resource "ravion_domain" "wildcard" {
  for_each = toset(local.wildcard_covered)

  name        = trimsuffix(each.value, ".${local.apex}")
  parent_fqdn = local.apex
}

# Per-service certificate covering the custom (non-wildcard) domains (<=10 SANs),
# attached to the cluster listener via Ravion.
resource "ravion_certificate" "svc" {
  count = length(local.custom_domains) > 0 ? 1 : 0

  role           = "instance"
  domains        = local.custom_domains
  aws_account_id = var.ravion_aws_account_id
  aws_region     = coalesce(var.ravion_aws_region, local.region)
  target_arn     = var.cluster_https_listener_arn

  lifecycle {
    precondition {
      condition     = length(local.custom_domains) == 0 || (var.ravion_aws_account_id != null && var.ravion_aws_account_id != "")
      error_message = "ravion_aws_account_id is required when the domains list includes a custom (non-wildcard) domain."
    }
    precondition {
      condition     = length(local.custom_domains) == 0 || (var.cluster_https_listener_arn != null && var.cluster_https_listener_arn != "")
      error_message = "cluster_https_listener_arn is required when the domains list includes a custom (non-wildcard) domain."
    }
    precondition {
      condition     = length(local.custom_domains) <= 10
      error_message = "A service may declare at most 10 custom (non-wildcard) domains (one cert per service)."
    }
  }
}

# Routing records the customer must add for each custom domain (one per FQDN).
resource "ravion_domain" "custom" {
  for_each = toset(local.custom_domains)

  name            = each.value
  target_dns_name = var.cluster_alb_dns_name
  target_zone_id  = var.cluster_alb_zone_id
}

# Single listener rule routing all of this service's hostnames to its target
# group. Blue/green controllers flip the action externally.
resource "aws_lb_listener_rule" "ravion" {
  count = local.ravion_managed && var.cluster_https_listener_arn != null && length(local.ravion_host_headers) > 0 ? 1 : 0

  listener_arn = var.cluster_https_listener_arn
  priority     = local.ravion_priority

  condition {
    host_header {
      values = local.ravion_host_headers
    }
  }

  action {
    type             = "forward"
    target_group_arn = local.ravion_target_group_arn
  }

  lifecycle {
    ignore_changes = [action]
  }
}
