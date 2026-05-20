################################################################################
# Ravion domain control plane — per-service domain allocations
#
# When the parent cluster module is configured for Ravion-managed
# domains (`module.ecs_cluster.ravion_managed_domains_enabled`), each
# entry in var.ravion_domains gets:
#
#   ravion_domain.this[d]            — child allocation under the cluster
#   ravion_dns_records.this[d]       — CNAME pointing the FQDN at the ALB
#   aws_lb_listener_rule.ravion[d]   — host-header rule on the cluster's
#                                       HTTPS listener
#
# No per-domain ACM cert — the cluster's wildcard covers every FQDN
# allocated under it via SNI. No ravion_managed_certificate either —
# the cluster's ravion_managed_certificate already advertises the cert.
#
# Empty var.ravion_domains = the service is reachable via the cluster's
# apex wildcard only; nothing is allocated here.
################################################################################

locals {
  ravion_managed = (
    var.ravion_parent_domain_allocation_id != null &&
    var.ravion_parent_domain_allocation_id != ""
  )
  ravion_has_listener = (
    var.ravion_cluster_https_listener_arn != null &&
    var.ravion_cluster_https_listener_arn != ""
  )
  ravion_domain_set = local.ravion_managed ? toset(var.ravion_domains) : toset([])

  # Deterministic per-(service, domain) priority so two services in the
  # same cluster don't collide on listener-rule priority. SHA-256 →
  # 16-bit hex digest → mod 49000 + offset 1000 to stay clear of the
  # lower reserved range. When the caller pins a base, sort the domain
  # slugs and assign +0, +1, +2, ... so re-applies stay stable.
  ravion_sorted_domains = sort(var.ravion_domains)
  ravion_priority_for_domain = {
    for idx, d in local.ravion_sorted_domains :
    d => (
      var.ravion_listener_rule_priority_base > 0
      ? var.ravion_listener_rule_priority_base + idx
      : (parseint(substr(sha256("${var.name}:${d}"), 0, 4), 16) % 49000) + 1000
    )
  }
}

# 1. Allocate one child FQDN per entry in var.ravion_domains.
resource "ravion_domain" "this" {
  for_each = local.ravion_domain_set

  dns_zone_id                 = var.ravion_dns_zone_id
  slug                        = each.value
  parent_domain_allocation_id = var.ravion_parent_domain_allocation_id
}

# 2. Routing CNAME — each FQDN points at the cluster's public ALB.
resource "ravion_dns_records" "this" {
  for_each = local.ravion_domain_set

  managed_domain_id = ravion_domain.this[each.value].id
  records = [{
    name = ravion_domain.this[each.value].fqdn
    type = "ALIAS"
    value = jsonencode({
      dns_name = var.ravion_cluster_alb_dns_name
      zone_id  = var.ravion_cluster_alb_zone_id
    })
  }]
}

# 3. Listener rule — host-header match routes each FQDN to this service's
# target group on the cluster's HTTPS listener. The cluster cert covers
# `*.<cluster-fqdn>` so SNI handshake succeeds without an explicit
# aws_lb_listener_certificate attachment.
resource "aws_lb_listener_rule" "ravion" {
  for_each = local.ravion_has_listener ? local.ravion_domain_set : toset([])

  listener_arn = var.ravion_cluster_https_listener_arn
  priority     = local.ravion_priority_for_domain[each.value]

  condition {
    host_header {
      values = [ravion_domain.this[each.value].fqdn]
    }
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this[0].arn
  }

  lifecycle {
    ignore_changes = [action]
  }

  tags = var.tags
}
