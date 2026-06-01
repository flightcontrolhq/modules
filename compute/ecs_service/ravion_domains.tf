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
  apex           = local.ravion_managed ? lower(var.cluster_parent_fqdn) : ""

  # Auto-FQDN used when the domains list is empty (matches the frontend default).
  auto_fqdn = local.ravion_managed ? "${coalesce(var.module_instance_given_id, var.name)}.${local.apex}" : ""

  # The effective list: the user's domains (or the auto-FQDN when empty),
  # normalized — lowercased, trailing dot + surrounding whitespace stripped,
  # empties dropped. Keeps classification consistent with DNS case-insensitivity
  # and the backend's lowercase sanitizeLabel.
  effective_domains = local.ravion_managed ? [
    for d in(length(var.domains) > 0 ? var.domains : [local.auto_fqdn]) :
    lower(trimsuffix(trimspace(d), ".")) if trimspace(d) != ""
  ] : []

  # Per-entry classification. wildcard-covered = "<leaf>.<apex>" with a non-empty
  # single label below the apex (the only shape the `*.<apex>` cert + ALIAS
  # cover). The non-empty-leaf guard keeps a malformed ".<apex>" out of the
  # wildcard bucket (an empty leaf would produce an invalid ALB host header).
  wildcard_covered = [
    for d in local.effective_domains : d
    if endswith(d, ".${local.apex}") && length(trimsuffix(d, ".${local.apex}")) > 0 && !strcontains(trimsuffix(d, ".${local.apex}"), ".")
  ]
  custom_domains = [
    for d in local.effective_domains : d
    if !(endswith(d, ".${local.apex}") && length(trimsuffix(d, ".${local.apex}")) > 0 && !strcontains(trimsuffix(d, ".${local.apex}"), "."))
  ]

  # Domains under the cluster apex that are NOT a single-label `<leaf>.<apex>`:
  # the bare apex itself, or a name more than one label deep. The `*.<apex>`
  # wildcard cert covers exactly one label, and the customer cannot add records
  # to the Ravion-managed zone, so these can never be satisfied — they fall into
  # custom_domains today and would silently emit a per-service cert + an
  # unwritable routing record. Fail the plan instead (the server-side
  # RejectCustomDomainUnderApex is the same backstop for direct-API callers).
  invalid_apex_domains = [
    for d in local.custom_domains : d
    if d == local.apex || endswith(d, ".${local.apex}")
  ]
  invalid_apex_domains_msg = join(", ", local.invalid_apex_domains)

  # All of this service's hostnames route to its target group. AWS ALB allows at
  # most 5 values in a single rule condition, so the host headers are split into
  # chunks of <=5 — one aws_lb_listener_rule per chunk (see below), each with its
  # own derived priority. (chunklist([], 5) == [], handled by the rule's guard.)
  ravion_host_headers       = local.effective_domains
  ravion_host_header_chunks = chunklist(local.ravion_host_headers, 5)

  # Base listener-rule priority. When ravion_listener_rule_priority is 0 (the
  # default) it is derived from sha256(name) using 12 hex chars (~48 bits) so the
  # collision probability stays low across many services sharing the cluster
  # listener; mod 48000 (instead of 49000) leaves headroom below the ALB max of
  # 50000 for the per-chunk offset (priority = base + chunk index). On a residual
  # collision ("priority already in use") set ravion_listener_rule_priority
  # explicitly to a free value.
  ravion_priority = var.ravion_listener_rule_priority > 0 ? var.ravion_listener_rule_priority : ((parseint(substr(sha256(var.name), 0, 12), 16) % 48000) + 1000)

  ravion_target_group_arn = (
    length(aws_lb_target_group.this) > 0 ? aws_lb_target_group.this[0].arn : (
      length(aws_lb_target_group.tg_1) > 0 ? aws_lb_target_group.tg_1[0].arn : null
    )
  )
}

# Plan-time authorization guard: a service may only nest its auto-domains under
# a cluster wildcard apex it actually references in its config. Fails the plan
# with a clear message if cluster_parent_fqdn was pointed at another cluster's
# apex the run doesn't reference. The control plane enforces the same rule at
# apply against a signed token claim (Dns:PARENT_APEX_UNAUTHORIZED), so this
# only moves the failure earlier.
data "ravion_parent_apex_check" "cluster" {
  count       = local.ravion_managed && length(local.wildcard_covered) > 0 ? 1 : 0
  parent_fqdn = local.apex
}

# Wildcard-covered domains (incl. the auto-FQDN): nest under the cluster
# wildcard. No per-service cert; the cluster `*.<apex>` ALIAS routes them.
resource "ravion_domain" "wildcard" {
  for_each = toset(local.wildcard_covered)

  name        = trimsuffix(each.value, ".${local.apex}")
  parent_fqdn = local.apex

  lifecycle {
    precondition {
      # try(...) allows when the check is skipped (count 0) or the apex isn't yet
      # resolvable (first apply before the cluster exists) — the apply-time guard
      # takes over there.
      condition     = try(one(data.ravion_parent_apex_check.cluster[*].authorized), true)
      error_message = "This service may not nest ${each.value} under ${local.apex}: this deployment does not reference that cluster. Set cluster_parent_fqdn from your own cluster's ravion_cluster_domain_fqdn output."
    }
  }
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
      condition     = length(local.invalid_apex_domains) == 0
      error_message = "Domains under the cluster apex must be a single label that rides the cluster wildcard, like checkout.${local.apex}. These entries are the bare apex or more than one label deep, so the wildcard certificate does not cover them and their routing record would have to live in the Ravion-managed zone (which you cannot edit): ${local.invalid_apex_domains_msg}. Use a single-label name under the apex, or a domain in a DNS zone you control."
    }
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

# One listener rule per chunk of <=5 host headers (AWS ALB's per-condition value
# quota), together routing all of this service's hostnames to its target group.
# Each chunk gets its own priority (base + chunk index). Blue/green controllers
# flip the action externally.
resource "aws_lb_listener_rule" "ravion" {
  for_each = local.ravion_managed && var.cluster_https_listener_arn != null && length(local.ravion_host_headers) > 0 ? {
    for idx, chunk in local.ravion_host_header_chunks : idx => chunk
  } : {}

  listener_arn = var.cluster_https_listener_arn
  priority     = local.ravion_priority + tonumber(each.key)

  condition {
    host_header {
      values = each.value
    }
  }

  action {
    type             = "forward"
    target_group_arn = local.ravion_target_group_arn
  }

  lifecycle {
    # A Ravion-managed service forwards its hostnames to its own target group, so
    # it must have a load balancer attachment. Without one ravion_target_group_arn
    # is null, which would otherwise surface as a cryptic provider-side
    # "target_group_arn must not be empty" at apply.
    precondition {
      condition     = !local.ravion_managed || local.enable_load_balancer
      error_message = "A Ravion-managed service (cluster_parent_fqdn set) requires an enabled load_balancer_attachment so its hostnames have a target group to forward to."
    }
    ignore_changes = [action]
  }
}

# Earlier revisions created a single count-based rule; migrate that instance to
# the first for_each chunk so adopting the chunked layout is not a destroy+create.
moved {
  from = aws_lb_listener_rule.ravion[0]
  to   = aws_lb_listener_rule.ravion["0"]
}
