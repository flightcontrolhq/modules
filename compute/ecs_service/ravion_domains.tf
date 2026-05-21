################################################################################
# Ravion domain control plane — per-service certificate groups (V2)
#
# A single var.ravion_certificate_groups list drives EVERYTHING. Two kinds:
#
#   ravion_auto — Inherit cluster wildcard cert. `domains` is an
#     optional list of DNS-safe leaf labels (e.g. `api`). Each label
#     becomes a `<label>-<hash>.<cluster-fqdn>` allocation under the
#     cluster wildcard. Empty list → ONE auto-allocation of the form
#     `<svc-given-id>-<random>.<cluster-fqdn>` (zero typing). No own
#     ACM cert (cluster wildcard covers via SNI). No own DNS records
#     (cluster's DNS routes the wildcard). Host-header rule per FQDN.
#
#   customer — Operator's own DnsProvider on the row. Each domain in
#     `domains` is a full FQDN posted via fqdn_override (server-side
#     validation rejects anything not under the provider's apex). The
#     group issues its OWN ACM cert covering all FQDNs, writes
#     validation + routing records via the provider variant
#     (route53_ravion / route53 / cloudflare), and SNI-attaches the
#     cert to the cluster's HTTPS listener.
#
# All kinds share the same listener and the same priority pool —
# collisions across kinds are prevented by seeding the sha256 priority
# hash with a per-kind discriminator.
################################################################################

locals {
  ravion_has_listener = (
    var.ravion_cluster_https_listener_arn != null &&
    var.ravion_cluster_https_listener_arn != ""
  )

  ravion_cluster_managed = (
    var.ravion_parent_domain_allocation_id != null &&
    var.ravion_parent_domain_allocation_id != ""
  )

  groups_by_name = { for g in var.ravion_certificate_groups : g.name => g }
}

################################################################################
# 1. ravion_auto groups — leaf labels under cluster wildcard, plus the
#    zero-typing auto-allocation for groups with empty `domains`.
################################################################################

locals {
  # ravion_auto groups split into two buckets:
  #   - named labels: each entry in `domains` → one allocation
  #   - auto-only:    `domains` empty → one allocation per group using
  #                   the service's module_instance_given_id as slug
  ravion_auto_groups = {
    for g in var.ravion_certificate_groups :
    g.name => g if g.kind == "ravion_auto"
  }

  # (group, slug) pairs for the named-label case.
  ravion_auto_label_pairs = local.ravion_cluster_managed ? merge([
    for g_name, g in local.ravion_auto_groups : {
      for d in g.domains : "${g_name}/${d}" => {
        group_name = g_name
        slug       = d
      }
    }
  ]...) : {}

  # Groups eligible for the implicit auto-allocation: empty `domains`
  # AND the service's given_id is available so we have a stable slug.
  ravion_auto_auto_groups = {
    for g_name, g in local.ravion_auto_groups :
    g_name => g
    if local.ravion_cluster_managed
    && length(g.domains) == 0
    && var.module_instance_given_id != null
    && var.module_instance_given_id != ""
  }

  # Per-pair deterministic listener-rule priorities. "auto:" seed
  # prevents collision with customer rules in the same cluster.
  auto_label_priority = {
    for k, _v in local.ravion_auto_label_pairs :
    k => (parseint(substr(sha256("auto:${var.name}:${k}"), 0, 4), 16) % 49000) + 1000
  }
  auto_auto_priority = {
    for g_name, _v in local.ravion_auto_auto_groups :
    g_name => (parseint(substr(sha256("auto:auto:${var.name}:${g_name}"), 0, 4), 16) % 49000) + 1000
  }
}

# 1a. Per-leaf-label allocation under cluster wildcard.
resource "ravion_domain" "ravion_auto_label" {
  for_each = local.ravion_auto_label_pairs

  dns_provider_id             = var.ravion_dns_provider_id
  slug                        = each.value.slug
  parent_domain_allocation_id = var.ravion_parent_domain_allocation_id

  lifecycle {
    precondition {
      condition     = var.ravion_dns_provider_id != null && var.ravion_dns_provider_id != ""
      error_message = "ravion_dns_provider_id must be set (wire it from module.ecs_cluster.ravion_dns_provider_id) when using ravion_auto certificate groups."
    }
  }
}

# 1b. Zero-typing auto allocation — one per ravion_auto group with
# empty `domains`. Uses the service's given_id as the slug.
resource "ravion_domain" "ravion_auto_auto" {
  for_each = local.ravion_auto_auto_groups

  dns_provider_id             = var.ravion_dns_provider_id
  slug                        = var.module_instance_given_id
  parent_domain_allocation_id = var.ravion_parent_domain_allocation_id

  lifecycle {
    precondition {
      condition     = var.ravion_dns_provider_id != null && var.ravion_dns_provider_id != ""
      error_message = "ravion_dns_provider_id must be set (wire it from module.ecs_cluster.ravion_dns_provider_id) when using ravion_auto certificate groups."
    }
  }
}

# 1c. Host-header rule per named-label FQDN.
resource "aws_lb_listener_rule" "ravion_auto_label" {
  for_each = local.ravion_has_listener ? local.ravion_auto_label_pairs : {}

  listener_arn = var.ravion_cluster_https_listener_arn
  priority     = local.auto_label_priority[each.key]

  condition {
    host_header {
      values = [ravion_domain.ravion_auto_label[each.key].fqdn]
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
    "ravion:kind"       = "ravion_auto"
  })
}

# 1d. Host-header rule per zero-typing auto-allocation.
resource "aws_lb_listener_rule" "ravion_auto_auto" {
  for_each = local.ravion_has_listener ? local.ravion_auto_auto_groups : {}

  listener_arn = var.ravion_cluster_https_listener_arn
  priority     = local.auto_auto_priority[each.key]

  condition {
    host_header {
      values = [ravion_domain.ravion_auto_auto[each.key].fqdn]
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
    "ravion:cert_group" = each.key
    "ravion:kind"       = "ravion_auto"
  })
}

################################################################################
# 2. customer groups — full FQDNs, own DnsProvider, own ACM cert
################################################################################

locals {
  customer_groups = { for g in var.ravion_certificate_groups : g.name => g if g.kind == "customer" }

  # Per-(group, fqdn) flat map for nested for_each on per-domain
  # resources (allocations, validation writes, routing writes,
  # listener rules). Key is "<group>/<fqdn>".
  customer_pairs = merge([
    for g in var.ravion_certificate_groups : {
      for d in g.domains : "${g.name}/${d}" => {
        group_name = g.name
        slug       = d
      }
    }
    if g.kind == "customer"
  ]...)

  customer_providers = {
    for name, _g in local.customer_groups :
    name => data.ravion_dns_provider.groups[name]
  }

  customer_priority_for_pair = {
    for k, _v in local.customer_pairs :
    k => (parseint(substr(sha256("cust:${var.name}:${k}"), 0, 4), 16) % 49000) + 1000
  }
}

# 2a. Per-FQDN allocations under the customer's DnsProvider.
resource "ravion_domain" "customer" {
  for_each = local.customer_pairs

  dns_provider_id = local.customer_providers[each.value.group_name].id
  fqdn_override   = each.value.slug
}

# 2b. ONE ACM cert per customer group, covering all its FQDNs.
resource "aws_acm_certificate" "customer" {
  for_each = local.customer_groups

  domain_name = ravion_domain.customer["${each.key}/${each.value.domains[0]}"].fqdn
  subject_alternative_names = [
    for d in slice(each.value.domains, 1, length(each.value.domains)) :
    ravion_domain.customer["${each.key}/${d}"].fqdn
  ]
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(var.tags, {
    "ravion:cert_group" = each.key
    "ravion:kind"       = "customer"
  })
}

# 2c. Per-(group, fqdn) validation options, flattened the same way as
# customer_pairs so nested for_each can fan out per provider variant.
locals {
  customer_validation_pairs = merge([
    for g_name, g in local.customer_groups : {
      for opt in aws_acm_certificate.customer[g_name].domain_validation_options :
      "${g_name}/${opt.domain_name}" => {
        group_name = g_name
        domain_key = "${g_name}/${opt.domain_name}"
        opt        = opt
        provider   = local.customer_providers[g_name]
      }
    }
  ]...)

  customer_validation_pairs_route53_ravion = {
    for k, v in local.customer_validation_pairs : k => v
    if v.provider.route53_ravion != null
  }
  customer_validation_pairs_route53 = {
    for k, v in local.customer_validation_pairs : k => v
    if v.provider.route53 != null
  }
  customer_validation_pairs_cloudflare = {
    for k, v in local.customer_validation_pairs : k => v
    if v.provider.cloudflare != null
  }
}

# 2d. ROUTE53_RAVION validation — Ravion's Route53 inline write.
resource "ravion_dns_records" "customer_validation_ravion" {
  for_each = local.customer_validation_pairs_route53_ravion

  managed_domain_id = ravion_domain.customer[each.value.domain_key].id
  records = [{
    name  = each.value.opt.resource_record_name
    type  = each.value.opt.resource_record_type
    value = each.value.opt.resource_record_value
    ttl   = 60
  }]
}

# 2e. ROUTE53 (customer) validation — customer's AWS write + Ravion metadata.
resource "aws_route53_record" "customer_validation_r53" {
  for_each = local.customer_validation_pairs_route53

  zone_id = each.value.provider.route53.hosted_zone_id
  name    = each.value.opt.resource_record_name
  type    = each.value.opt.resource_record_type
  records = [each.value.opt.resource_record_value]
  ttl     = 60
}

resource "ravion_dns_records" "customer_validation_metadata_r53" {
  for_each = local.customer_validation_pairs_route53

  managed_domain_id = ravion_domain.customer[each.value.domain_key].id
  records = [{
    name  = each.value.opt.resource_record_name
    type  = each.value.opt.resource_record_type
    value = each.value.opt.resource_record_value
    ttl   = 60
  }]
  depends_on = [aws_route53_record.customer_validation_r53]
}

# 2f. CLOUDFLARE validation — customer's CF write + Ravion metadata.
resource "cloudflare_dns_record" "customer_validation_cf" {
  for_each = local.customer_validation_pairs_cloudflare

  zone_id = each.value.provider.cloudflare.zone_id
  name    = trimsuffix(each.value.opt.resource_record_name, ".")
  type    = each.value.opt.resource_record_type
  content = trimsuffix(each.value.opt.resource_record_value, ".")
  ttl     = 60
  proxied = false
}

resource "ravion_dns_records" "customer_validation_metadata_cf" {
  for_each = local.customer_validation_pairs_cloudflare

  managed_domain_id = ravion_domain.customer[each.value.domain_key].id
  records = [{
    name  = each.value.opt.resource_record_name
    type  = each.value.opt.resource_record_type
    value = each.value.opt.resource_record_value
    ttl   = 60
  }]
  depends_on = [cloudflare_dns_record.customer_validation_cf]
}

# 2g. Cert validation — waits for the right writer per variant.
resource "aws_acm_certificate_validation" "customer" {
  for_each = local.customer_groups

  certificate_arn = aws_acm_certificate.customer[each.key].arn
  validation_record_fqdns = concat(
    [
      for k, v in local.customer_validation_pairs_route53_ravion : ravion_dns_records.customer_validation_ravion[k].fqdns[0]
      if v.group_name == each.key
    ],
    [
      for k, v in local.customer_validation_pairs_route53 : ravion_dns_records.customer_validation_metadata_r53[k].fqdns[0]
      if v.group_name == each.key
    ],
    [
      for k, v in local.customer_validation_pairs_cloudflare : ravion_dns_records.customer_validation_metadata_cf[k].fqdns[0]
      if v.group_name == each.key
    ],
  )
}

# 2h. Register cert metadata at Ravion (one per customer group).
resource "ravion_managed_certificate" "customer" {
  for_each = local.customer_groups

  cert_arn = aws_acm_certificate_validation.customer[each.key].certificate_arn
  status   = "ISSUED"
  scope    = "SERVICE"
  managed_domain_ids = [
    for d in each.value.domains :
    ravion_domain.customer["${each.key}/${d}"].managed_domain_id
  ]
  issued_at  = aws_acm_certificate.customer[each.key].not_before
  expires_at = aws_acm_certificate.customer[each.key].not_after
}

# 2i. SNI cert attachment — cluster's HTTPS listener already owns the
# default cert (wildcard). Per-group customer cert is additive.
resource "aws_lb_listener_certificate" "customer" {
  for_each = local.ravion_has_listener ? local.customer_groups : {}

  listener_arn    = var.ravion_cluster_https_listener_arn
  certificate_arn = aws_acm_certificate_validation.customer[each.key].certificate_arn
}

# 2j. ROUTE53_RAVION routing — Ravion's Route53 ALIAS inline write.
resource "ravion_dns_records" "customer_routing_ravion" {
  for_each = {
    for k, v in local.customer_pairs : k => v
    if local.customer_providers[v.group_name].route53_ravion != null
  }

  managed_domain_id = ravion_domain.customer[each.key].id
  records = [{
    name = ravion_domain.customer[each.key].fqdn
    type = "ALIAS"
    value = jsonencode({
      dns_name = var.ravion_cluster_alb_dns_name
      zone_id  = var.ravion_cluster_alb_zone_id
    })
  }]
}

# 2k. ROUTE53 (customer) routing — customer AWS write + Ravion metadata.
resource "aws_route53_record" "customer_routing_r53" {
  for_each = {
    for k, v in local.customer_pairs : k => v
    if local.customer_providers[v.group_name].route53 != null
  }

  zone_id = local.customer_providers[each.value.group_name].route53.hosted_zone_id
  name    = ravion_domain.customer[each.key].fqdn
  type    = "A"

  alias {
    name                   = var.ravion_cluster_alb_dns_name
    zone_id                = var.ravion_cluster_alb_zone_id
    evaluate_target_health = true
  }
}

resource "ravion_dns_records" "customer_routing_metadata_r53" {
  for_each = {
    for k, v in local.customer_pairs : k => v
    if local.customer_providers[v.group_name].route53 != null
  }

  managed_domain_id = ravion_domain.customer[each.key].id
  records = [{
    name = ravion_domain.customer[each.key].fqdn
    type = "ALIAS"
    value = jsonencode({
      dns_name = var.ravion_cluster_alb_dns_name
      zone_id  = var.ravion_cluster_alb_zone_id
    })
  }]
  depends_on = [aws_route53_record.customer_routing_r53]
}

# 2l. CLOUDFLARE routing — customer CF write + Ravion metadata.
resource "cloudflare_dns_record" "customer_routing_cf" {
  for_each = {
    for k, v in local.customer_pairs : k => v
    if local.customer_providers[v.group_name].cloudflare != null
  }

  zone_id = local.customer_providers[each.value.group_name].cloudflare.zone_id
  name    = ravion_domain.customer[each.key].fqdn
  type    = "CNAME"
  content = var.ravion_cluster_alb_dns_name
  ttl     = 60
  proxied = false
}

resource "ravion_dns_records" "customer_routing_metadata_cf" {
  for_each = {
    for k, v in local.customer_pairs : k => v
    if local.customer_providers[v.group_name].cloudflare != null
  }

  managed_domain_id = ravion_domain.customer[each.key].id
  records = [{
    name  = ravion_domain.customer[each.key].fqdn
    type  = "CNAME"
    value = var.ravion_cluster_alb_dns_name
    ttl   = 60
  }]
  depends_on = [cloudflare_dns_record.customer_routing_cf]
}

# 2m. Host-header rule per customer FQDN.
resource "aws_lb_listener_rule" "customer" {
  for_each = local.ravion_has_listener ? local.customer_pairs : {}

  listener_arn = var.ravion_cluster_https_listener_arn
  priority     = local.customer_priority_for_pair[each.key]

  condition {
    host_header {
      values = [ravion_domain.customer[each.key].fqdn]
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
    "ravion:kind"       = "customer"
  })
}
