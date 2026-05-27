################################################################################
# Ravion-managed service domain (optional)
################################################################################
# Wired when cluster_parent_fqdn is set (piped from ecs_cluster).
#
#   Mode A (domains = []): an auto-FQDN <name>.<cluster-apex> rides the cluster
#     wildcard cert — only a listener rule + routing record, no per-service cert.
#   Mode B (domains = [...]): a per-service cert (<=10 SANs) attached to the
#     cluster listener via Ravion; the auto-FQDN stays until the customs are
#     healthy, then ravion_auto_domain_status flips retired -> auto is destroyed.

locals {
  ravion_managed   = var.cluster_parent_fqdn != null && var.cluster_parent_fqdn != ""
  ravion_mode_b    = local.ravion_managed && length(var.domains) > 0
  ravion_retired   = local.ravion_mode_b ? try(data.ravion_auto_domain_status.auto[0].retired, false) : false
  ravion_auto_live = local.ravion_managed && !local.ravion_retired

  ravion_priority = var.ravion_listener_rule_priority > 0 ? var.ravion_listener_rule_priority : ((parseint(substr(sha256(var.name), 0, 4), 16) % 49000) + 1000)

  ravion_host_headers = concat(
    [for d in ravion_domain.auto : d.fqdn],
    local.ravion_mode_b ? var.domains : [],
  )

  ravion_target_group_arn = (
    length(aws_lb_target_group.this) > 0 ? aws_lb_target_group.this[0].arn : (
      length(aws_lb_target_group.tg_1) > 0 ? aws_lb_target_group.tg_1[0].arn : null
    )
  )
}

data "ravion_auto_domain_status" "auto" {
  count = local.ravion_managed ? 1 : 0

  parent_domain_id = var.cluster_parent_fqdn
  name             = var.name
}

# Mode A auto-FQDN under the cluster wildcard (no per-service cert).
resource "ravion_domain" "auto" {
  count = local.ravion_auto_live ? 1 : 0

  name        = var.name
  parent_fqdn = var.cluster_parent_fqdn
}

# Mode B per-service certificate (<=10 SANs), attached to the cluster listener.
resource "ravion_certificate" "svc" {
  count = local.ravion_mode_b ? 1 : 0

  role           = "instance"
  domains        = var.domains
  aws_account_id = var.ravion_aws_account_id
  aws_region     = coalesce(var.ravion_aws_region, local.region)
  target_arn     = var.cluster_https_listener_arn

  lifecycle {
    precondition {
      condition     = !local.ravion_mode_b || (var.ravion_aws_account_id != null && var.ravion_aws_account_id != "")
      error_message = "ravion_aws_account_id is required when domains is non-empty."
    }
    precondition {
      condition     = !local.ravion_mode_b || (var.cluster_https_listener_arn != null && var.cluster_https_listener_arn != "")
      error_message = "cluster_https_listener_arn is required when domains is non-empty."
    }
    precondition {
      condition     = length(var.domains) <= 10
      error_message = "A service may declare at most 10 custom domains (one cert per service)."
    }
  }
}

# Mode B routing records the customer must add (one per custom FQDN).
resource "ravion_domain" "custom" {
  for_each = local.ravion_mode_b ? toset(var.domains) : toset([])

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
