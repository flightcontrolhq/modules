################################################################################
# Ravion domain control plane — service auto-domain
#
# Allocates a child FQDN under the cluster's wildcard (e.g.
# `<svc-name>-<hash>.<cluster-fqdn>`) so the service inherits the
# cluster's wildcard cert via SNI without needing its own ACM cert.
#
# Resources:
#   ravion_domain.auto              — child allocation under cluster
#   ravion_dns_records.auto_routing — CNAME pointing the FQDN at the
#                                      cluster's public ALB
#   aws_lb_listener_rule.ravion     — host-header rule routing the FQDN
#                                      to this service's target group
#
# No per-service ACM cert — the cluster's wildcard covers this FQDN.
# No ravion_managed_certificate either — the cluster's
# ravion_managed_certificate already advertises the cert.
################################################################################

locals {
  ravion_managed      = var.ravion_parent_domain_allocation_id != null && var.ravion_parent_domain_allocation_id != ""
  ravion_has_listener = var.ravion_cluster_https_listener_arn != null && var.ravion_cluster_https_listener_arn != ""
  # Deterministic per-service priority so two services in the same
  # cluster don't collide on listener-rule priority. SHA-256 → 16-bit
  # hex digest → mod 49000 + offset 1000 to stay clear of the lower
  # reserved range.
  ravion_priority = var.ravion_listener_rule_priority > 0 ? var.ravion_listener_rule_priority : (parseint(substr(sha256(var.name), 0, 4), 16) % 49000) + 1000
}

# 1. Allocate the child FQDN under the cluster.
resource "ravion_domain" "auto" {
  count                       = local.ravion_managed ? 1 : 0
  dns_zone_id                 = var.ravion_dns_zone_id
  slug                        = coalesce(var.ravion_service_slug, var.name)
  parent_domain_allocation_id = var.ravion_parent_domain_allocation_id
}

# 2. Routing CNAME — FQDN points at the cluster's public ALB. The
# cluster's ravion_dns_records.cluster_routing handles the wildcard
# apex; this is the per-service leaf so DNS resolution hits the ALB
# directly.
resource "ravion_dns_records" "auto_routing" {
  count             = local.ravion_managed ? 1 : 0
  managed_domain_id = ravion_domain.auto[0].id
  records = [{
    name = ravion_domain.auto[0].fqdn
    type = "ALIAS"
    value = jsonencode({
      dns_name = var.ravion_cluster_alb_dns_name
      zone_id  = var.ravion_cluster_alb_zone_id
    })
  }]
}

# 3. Listener rule — host-header match routes this service's FQDN to
# the service's target group on the cluster's HTTPS listener. The
# cluster cert covers `*.<cluster-fqdn>` so SNI handshake succeeds
# without an explicit aws_lb_listener_certificate attachment.
resource "aws_lb_listener_rule" "ravion" {
  count = local.ravion_managed && local.ravion_has_listener ? 1 : 0

  listener_arn = var.ravion_cluster_https_listener_arn
  priority     = local.ravion_priority

  condition {
    host_header {
      values = [ravion_domain.auto[0].fqdn]
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
