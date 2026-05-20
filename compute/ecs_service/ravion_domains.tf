################################################################################
# Ravion domain control plane — per-service domain allocations (V2)
#
# When the parent cluster module is configured for Ravion-managed
# domains (`module.ecs_cluster.ravion_managed_domains_enabled`), each
# entry in var.ravion_domains gets:
#
#   ravion_domain.this[d]                     — child allocation under
#                                                 the cluster
#   <variant>_record.routing_<d>              — actual CNAME write
#                                                 (Route53 / Cloudflare)
#   ravion_dns_records.this[d]                — metadata-only sibling
#                                                 (depends_on the real
#                                                 record write)
#   aws_lb_listener_rule.ravion[d]            — host-header rule on the
#                                                 cluster's HTTPS listener
#
# No per-domain ACM cert — the cluster's wildcard covers every FQDN
# allocated under it via SNI. No ravion_managed_certificate either —
# the cluster's ravion_managed_certificate already advertises the cert.
#
# Empty var.ravion_domains = service is reachable via the cluster's
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

# 0. Auto-mode allocation (zero-config). One URL per service when
#    ravion_auto_subdomain is on AND the parent cluster wildcard is
#    wired. Slug = service's given_id → server derives
#    `<given-id>-<random>.<cluster-fqdn>`. No customer typing.
locals {
  ravion_auto_enabled = (
    local.ravion_managed &&
    var.ravion_auto_subdomain &&
    var.module_instance_given_id != null &&
    var.module_instance_given_id != ""
  )
}

resource "ravion_domain" "auto" {
  count = local.ravion_auto_enabled ? 1 : 0

  dns_provider_id             = var.ravion_dns_provider_id
  slug                        = var.module_instance_given_id
  parent_domain_allocation_id = var.ravion_parent_domain_allocation_id
}

# 1. Allocate one child FQDN per entry in var.ravion_domains.
resource "ravion_domain" "this" {
  for_each = local.ravion_domain_set

  dns_provider_id             = var.ravion_dns_provider_id
  slug                        = each.value
  parent_domain_allocation_id = var.ravion_parent_domain_allocation_id
}

# ---- 2a. ROUTE53_RAVION routing records ----------------------------------
# Ravion's own Route53 — RavionRoute53Writer writes the ALIAS inline.
resource "ravion_dns_records" "ravion" {
  for_each = local.is_route53_ravion ? local.ravion_domain_set : toset([])

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

# ---- 2b. ROUTE53 (customer) routing records ------------------------------
resource "aws_route53_record" "this_r53" {
  for_each = local.is_route53 ? local.ravion_domain_set : toset([])

  zone_id = local.dns_provider.route53.hosted_zone_id
  name    = ravion_domain.this[each.value].fqdn
  type    = "A"

  alias {
    name                   = var.ravion_cluster_alb_dns_name
    zone_id                = var.ravion_cluster_alb_zone_id
    evaluate_target_health = true
  }
}

resource "ravion_dns_records" "metadata_r53" {
  for_each = local.is_route53 ? local.ravion_domain_set : toset([])

  managed_domain_id = ravion_domain.this[each.value].id
  records = [{
    name = ravion_domain.this[each.value].fqdn
    type = "ALIAS"
    value = jsonencode({
      dns_name = var.ravion_cluster_alb_dns_name
      zone_id  = var.ravion_cluster_alb_zone_id
    })
  }]
  depends_on = [aws_route53_record.this_r53]
}

# ---- 2c. CLOUDFLARE routing records --------------------------------------
# Cloudflare doesn't do AWS ALIAS records — CNAME at the child FQDN
# pointing at the cluster's ALB is functionally equivalent (each
# service FQDN is a non-apex label under the cluster's wildcard).
resource "cloudflare_dns_record" "this_cf" {
  for_each = local.is_cloudflare ? local.ravion_domain_set : toset([])

  zone_id = local.dns_provider.cloudflare.zone_id
  name    = ravion_domain.this[each.value].fqdn
  type    = "CNAME"
  content = var.ravion_cluster_alb_dns_name
  ttl     = 60
  proxied = false
}

resource "ravion_dns_records" "metadata_cf" {
  for_each = local.is_cloudflare ? local.ravion_domain_set : toset([])

  managed_domain_id = ravion_domain.this[each.value].id
  records = [{
    name  = ravion_domain.this[each.value].fqdn
    type  = "CNAME"
    value = var.ravion_cluster_alb_dns_name
    ttl   = 60
  }]
  depends_on = [cloudflare_dns_record.this_cf]
}

# 3. Listener rule — host-header match routes each FQDN to this service's
# target group on the cluster's HTTPS listener. The cluster cert covers
# `*.<cluster-fqdn>` so SNI handshake succeeds without an explicit
# aws_lb_listener_certificate attachment. Same rule per variant —
# host-header matching is variant-agnostic.
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

################################################################################
# Per-service certificate groups
#
# Independent of the cluster wildcard. Each group:
#   * Allocates ONE ravion_domain per domain slug under the group's
#     resolved DnsProvider (apex derived server-side from the provider).
#   * Issues ONE ACM cert covering all the group's FQDNs (primary +
#     SANs). Capped at 10 names per group (ACM default; raise the AWS
#     quota first if you need more).
#   * Writes per-domain validation records via the group's variant
#     (route53_ravion / route53 / cloudflare). Customer-owned variants
#     write the actual records; Ravion records metadata after-the-fact.
#   * Attaches the cert to the cluster's HTTPS listener via
#     aws_lb_listener_certificate so SNI handshake finds it.
#   * Adds host-header listener rules routing each FQDN to this
#     service's target group.
#
# Groups are ADDITIVE to var.ravion_domains — ungrouped slugs still
# inherit the cluster wildcard via SNI as before.
################################################################################

locals {
  # Flatten (group, domain) into a single map for nested for_each
  # against per-domain resources. The key is "<group>/<fqdn>" so two
  # groups can list the same fqdn without TF state collision.
  group_domain_pairs = merge([
    for g in var.ravion_certificate_groups : {
      for d in g.domains : "${g.name}/${d}" => {
        group_name = g.name
        # Slug field name kept for backwards-compat with the per-row
        # resource that consumed it; value is the full FQDN now.
        slug = d
      }
    }
  ]...)

  # Per-group resolved provider record, indexed by group name. Used to
  # dispatch the per-variant validation + routing writes.
  group_providers = {
    for g in var.ravion_certificate_groups :
    g.name => data.ravion_dns_provider.groups[g.name]
  }

  # Per-(group, domain) deterministic listener-rule priority. Layered
  # on top of the existing ravion_priority_for_domain offset so group
  # rules and ungrouped-domain rules don't collide. Uses a different
  # hash seed ("g:") to avoid accidental overlap when the same slug
  # appears in both var.ravion_domains and a group.
  group_priority_for_pair = {
    for k, pair in local.group_domain_pairs :
    k => (parseint(substr(sha256("g:${var.name}:${pair.group_name}:${pair.slug}"), 0, 4), 16) % 49000) + 1000
  }
}

# 1. Per-domain allocations under the group's provider. Each entry
#    is a FULL FQDN posted via fqdn_override — api-go validates it
#    lives under the resolved DnsProvider's apex.
resource "ravion_domain" "group" {
  for_each = local.group_domain_pairs

  dns_provider_id = local.group_providers[each.value.group_name].id
  fqdn_override   = each.value.slug
}

# 2. ONE ACM cert per group (primary + SANs). Customer's AWS account,
#    applied by their TF runner. The first FQDN is the primary name;
#    the rest become subject_alternative_names.
resource "aws_acm_certificate" "group" {
  for_each = { for g in var.ravion_certificate_groups : g.name => g }

  domain_name = ravion_domain.group["${each.key}/${each.value.domains[0]}"].fqdn
  subject_alternative_names = [
    for d in slice(each.value.domains, 1, length(each.value.domains)) :
    ravion_domain.group["${each.key}/${d}"].fqdn
  ]
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(var.tags, {
    "ravion:cert_group" = each.key
  })
}

# Helper local: per-(group, domain) validation options, flattened the
# same way as group_domain_pairs so a nested for_each can fan out to
# concrete writer resources without TF map-key gymnastics.
locals {
  group_validation_pairs = merge([
    for g in var.ravion_certificate_groups : {
      for opt in aws_acm_certificate.group[g.name].domain_validation_options :
      "${g.name}/${opt.domain_name}" => {
        group_name = g.name
        domain_key = "${g.name}/${opt.domain_name}"
        opt        = opt
        provider   = local.group_providers[g.name]
      }
    }
  ]...)

  # Per-variant subsets used as for_each. Switching on a member
  # attribute would force unknown-at-plan-time iteration; precomputing
  # the keyed subsets keeps plans deterministic.
  group_validation_pairs_route53_ravion = {
    for k, v in local.group_validation_pairs : k => v
    if v.provider.route53_ravion != null
  }
  group_validation_pairs_route53 = {
    for k, v in local.group_validation_pairs : k => v
    if v.provider.route53 != null
  }
  group_validation_pairs_cloudflare = {
    for k, v in local.group_validation_pairs : k => v
    if v.provider.cloudflare != null
  }
}

# 3a. ROUTE53_RAVION validation — Ravion's Route53 inline write.
resource "ravion_dns_records" "group_validation_ravion" {
  for_each = local.group_validation_pairs_route53_ravion

  managed_domain_id = ravion_domain.group[each.value.domain_key].id
  records = [{
    name  = each.value.opt.resource_record_name
    type  = each.value.opt.resource_record_type
    value = each.value.opt.resource_record_value
    ttl   = 60
  }]
}

# 3b. ROUTE53 (customer) validation — customer's AWS write + Ravion metadata.
resource "aws_route53_record" "group_validation_r53" {
  for_each = local.group_validation_pairs_route53

  zone_id = each.value.provider.route53.hosted_zone_id
  name    = each.value.opt.resource_record_name
  type    = each.value.opt.resource_record_type
  records = [each.value.opt.resource_record_value]
  ttl     = 60
}

resource "ravion_dns_records" "group_validation_metadata_r53" {
  for_each = local.group_validation_pairs_route53

  managed_domain_id = ravion_domain.group[each.value.domain_key].id
  records = [{
    name  = each.value.opt.resource_record_name
    type  = each.value.opt.resource_record_type
    value = each.value.opt.resource_record_value
    ttl   = 60
  }]
  depends_on = [aws_route53_record.group_validation_r53]
}

# 3c. CLOUDFLARE validation — customer's CF write + Ravion metadata.
resource "cloudflare_dns_record" "group_validation_cf" {
  for_each = local.group_validation_pairs_cloudflare

  zone_id = each.value.provider.cloudflare.zone_id
  name    = trimsuffix(each.value.opt.resource_record_name, ".")
  type    = each.value.opt.resource_record_type
  content = trimsuffix(each.value.opt.resource_record_value, ".")
  ttl     = 60
  proxied = false
}

resource "ravion_dns_records" "group_validation_metadata_cf" {
  for_each = local.group_validation_pairs_cloudflare

  managed_domain_id = ravion_domain.group[each.value.domain_key].id
  records = [{
    name  = each.value.opt.resource_record_name
    type  = each.value.opt.resource_record_type
    value = each.value.opt.resource_record_value
    ttl   = 60
  }]
  depends_on = [cloudflare_dns_record.group_validation_cf]
}

# 4. Cert validation — collects validation FQDNs from whichever writer
#    handled each domain in the group, waits for ACM.
resource "aws_acm_certificate_validation" "group" {
  for_each = { for g in var.ravion_certificate_groups : g.name => g }

  certificate_arn = aws_acm_certificate.group[each.key].arn
  validation_record_fqdns = concat(
    [
      for k, v in local.group_validation_pairs_route53_ravion : ravion_dns_records.group_validation_ravion[k].fqdns[0]
      if v.group_name == each.key
    ],
    [
      for k, v in local.group_validation_pairs_route53 : ravion_dns_records.group_validation_metadata_r53[k].fqdns[0]
      if v.group_name == each.key
    ],
    [
      for k, v in local.group_validation_pairs_cloudflare : ravion_dns_records.group_validation_metadata_cf[k].fqdns[0]
      if v.group_name == each.key
    ],
  )
}

# 5. Register cert metadata at Ravion (one per group).
resource "ravion_managed_certificate" "group" {
  for_each = { for g in var.ravion_certificate_groups : g.name => g }

  cert_arn = aws_acm_certificate_validation.group[each.key].certificate_arn
  status   = "ISSUED"
  scope    = "SERVICE"
  managed_domain_ids = [
    for d in each.value.domains :
    ravion_domain.group["${each.key}/${d}"].managed_domain_id
  ]
  issued_at  = aws_acm_certificate.group[each.key].not_before
  expires_at = aws_acm_certificate.group[each.key].not_after
}

# 6. Attach each group's cert to the cluster's HTTPS listener as an
#    SNI cert. The cluster already owns the default cert (wildcard),
#    so these are additive — SNI handshake picks the most specific
#    match.
resource "aws_lb_listener_certificate" "group" {
  for_each = local.ravion_has_listener ? { for g in var.ravion_certificate_groups : g.name => g } : {}

  listener_arn    = var.ravion_cluster_https_listener_arn
  certificate_arn = aws_acm_certificate_validation.group[each.key].certificate_arn
}

# 7a. Per-domain ROUTE53_RAVION routing record.
resource "ravion_dns_records" "group_routing_ravion" {
  for_each = {
    for k, v in local.group_domain_pairs : k => v
    if local.group_providers[v.group_name].route53_ravion != null
  }

  managed_domain_id = ravion_domain.group[each.key].id
  records = [{
    name = ravion_domain.group[each.key].fqdn
    type = "ALIAS"
    value = jsonencode({
      dns_name = var.ravion_cluster_alb_dns_name
      zone_id  = var.ravion_cluster_alb_zone_id
    })
  }]
}

# 7b. Per-domain ROUTE53 (customer) routing record.
resource "aws_route53_record" "group_routing_r53" {
  for_each = {
    for k, v in local.group_domain_pairs : k => v
    if local.group_providers[v.group_name].route53 != null
  }

  zone_id = local.group_providers[each.value.group_name].route53.hosted_zone_id
  name    = ravion_domain.group[each.key].fqdn
  type    = "A"

  alias {
    name                   = var.ravion_cluster_alb_dns_name
    zone_id                = var.ravion_cluster_alb_zone_id
    evaluate_target_health = true
  }
}

resource "ravion_dns_records" "group_routing_metadata_r53" {
  for_each = {
    for k, v in local.group_domain_pairs : k => v
    if local.group_providers[v.group_name].route53 != null
  }

  managed_domain_id = ravion_domain.group[each.key].id
  records = [{
    name = ravion_domain.group[each.key].fqdn
    type = "ALIAS"
    value = jsonencode({
      dns_name = var.ravion_cluster_alb_dns_name
      zone_id  = var.ravion_cluster_alb_zone_id
    })
  }]
  depends_on = [aws_route53_record.group_routing_r53]
}

# 7c. Per-domain CLOUDFLARE routing record.
resource "cloudflare_dns_record" "group_routing_cf" {
  for_each = {
    for k, v in local.group_domain_pairs : k => v
    if local.group_providers[v.group_name].cloudflare != null
  }

  zone_id = local.group_providers[each.value.group_name].cloudflare.zone_id
  name    = ravion_domain.group[each.key].fqdn
  type    = "CNAME"
  content = var.ravion_cluster_alb_dns_name
  ttl     = 60
  proxied = false
}

resource "ravion_dns_records" "group_routing_metadata_cf" {
  for_each = {
    for k, v in local.group_domain_pairs : k => v
    if local.group_providers[v.group_name].cloudflare != null
  }

  managed_domain_id = ravion_domain.group[each.key].id
  records = [{
    name  = ravion_domain.group[each.key].fqdn
    type  = "CNAME"
    value = var.ravion_cluster_alb_dns_name
    ttl   = 60
  }]
  depends_on = [cloudflare_dns_record.group_routing_cf]
}

# 8. Per-domain host-header listener rules pointing at this service's
#    target group. Variant-agnostic — once the cert is attached + the
#    DNS routing record points at the ALB, the listener rule does the
#    HTTP-level routing.
resource "aws_lb_listener_rule" "group" {
  for_each = local.ravion_has_listener ? local.group_domain_pairs : {}

  listener_arn = var.ravion_cluster_https_listener_arn
  priority     = local.group_priority_for_pair[each.key]

  condition {
    host_header {
      values = [ravion_domain.group[each.key].fqdn]
    }
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this[0].arn
  }

  lifecycle {
    ignore_changes = [action]
  }

  tags = merge(var.tags, {
    "ravion:cert_group" = each.value.group_name
  })
}

################################################################################
# Auto-mode routing records + listener rule (zero-config URL)
#
# Same per-variant dispatch as the per-domain blocks above, but for
# the single auto-allocation. Count gating is 1 when auto-mode is on
# AND the matching provider variant resolves; 0 otherwise.
################################################################################

# Auto: ROUTE53_RAVION routing — Ravion's Route53 ALIAS, inline write.
resource "ravion_dns_records" "auto_ravion" {
  count = local.ravion_auto_enabled && local.is_route53_ravion ? 1 : 0

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

# Auto: ROUTE53 (customer) routing — customer AWS write + Ravion metadata.
resource "aws_route53_record" "auto_r53" {
  count = local.ravion_auto_enabled && local.is_route53 ? 1 : 0

  zone_id = local.dns_provider.route53.hosted_zone_id
  name    = ravion_domain.auto[0].fqdn
  type    = "A"

  alias {
    name                   = var.ravion_cluster_alb_dns_name
    zone_id                = var.ravion_cluster_alb_zone_id
    evaluate_target_health = true
  }
}

resource "ravion_dns_records" "auto_metadata_r53" {
  count = local.ravion_auto_enabled && local.is_route53 ? 1 : 0

  managed_domain_id = ravion_domain.auto[0].id
  records = [{
    name = ravion_domain.auto[0].fqdn
    type = "ALIAS"
    value = jsonencode({
      dns_name = var.ravion_cluster_alb_dns_name
      zone_id  = var.ravion_cluster_alb_zone_id
    })
  }]
  depends_on = [aws_route53_record.auto_r53]
}

# Auto: CLOUDFLARE routing — customer CF write + Ravion metadata.
resource "cloudflare_dns_record" "auto_cf" {
  count = local.ravion_auto_enabled && local.is_cloudflare ? 1 : 0

  zone_id = local.dns_provider.cloudflare.zone_id
  name    = ravion_domain.auto[0].fqdn
  type    = "CNAME"
  content = var.ravion_cluster_alb_dns_name
  ttl     = 60
  proxied = false
}

resource "ravion_dns_records" "auto_metadata_cf" {
  count = local.ravion_auto_enabled && local.is_cloudflare ? 1 : 0

  managed_domain_id = ravion_domain.auto[0].id
  records = [{
    name  = ravion_domain.auto[0].fqdn
    type  = "CNAME"
    value = var.ravion_cluster_alb_dns_name
    ttl   = 60
  }]
  depends_on = [cloudflare_dns_record.auto_cf]
}

# Auto: host-header listener rule. Same priority space as the per-
# domain rules; seeded with "auto:" to avoid collision.
resource "aws_lb_listener_rule" "auto" {
  count = local.ravion_auto_enabled && local.ravion_has_listener ? 1 : 0

  listener_arn = var.ravion_cluster_https_listener_arn
  priority     = (parseint(substr(sha256("auto:${var.name}"), 0, 4), 16) % 49000) + 1000

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
