################################################################################
# Ravion cert-groups shared child module — dispatch by kind.
#
#   ravion_auto — Inherit cluster wildcard cert (no own ACM cert). Each
#     domain in `domains` becomes `<label>-<hash>.<cluster-fqdn>` under
#     var.ravion_parent_domain_allocation_id. Empty `domains` → ONE
#     auto-allocation `<module_instance_given_id>-<random>.<cluster-fqdn>`
#     (zero typing). Host-header rule per FQDN routed to var.target_group_arn.
#
#   customer — Operator's own DnsProvider on the row. Each domain is a
#     full FQDN posted via fqdn_override. The group issues its OWN ACM
#     cert covering all FQDNs, writes validation + routing records via
#     the provider variant (route53_ravion / route53 / cloudflare),
#     SNI-attaches the cert to var.listener_arn, and adds host-header
#     rules.
#
# Listener-rule priorities use a 32-bit sha256-derived bucket index
# modulo 49000 (ALB priority range 1000..50000). Per-kind seed prefix
# prevents collisions across kinds within the same listener.
################################################################################

locals {
  has_listener     = var.listener_arn != null && var.listener_arn != ""
  has_target_group = var.target_group_arn != null && var.target_group_arn != ""
  cluster_managed  = var.ravion_parent_domain_allocation_id != null && var.ravion_parent_domain_allocation_id != ""
}

################################################################################
# 1. ravion_auto groups
################################################################################

locals {
  ravion_auto_groups = {
    for g in var.cert_groups :
    g.name => g if g.kind == "ravion_auto"
  }

  ravion_auto_label_pairs = local.cluster_managed ? merge([
    for g_name, g in local.ravion_auto_groups : {
      for d in g.domains : "${g_name}/${d}" => {
        group_name = g_name
        slug       = d
      }
    }
  ]...) : {}

  ravion_auto_auto_groups = {
    for g_name, g in local.ravion_auto_groups :
    g_name => g
    if local.cluster_managed
    && length(g.domains) == 0
    && var.module_instance_given_id != null
    && var.module_instance_given_id != ""
  }

  auto_label_priority = {
    for k, _v in local.ravion_auto_label_pairs :
    k => (parseint(substr(sha256("auto:${var.name}:${k}"), 0, 8), 16) % 49000) + 1000
  }
  auto_auto_priority = {
    for g_name, _v in local.ravion_auto_auto_groups :
    g_name => (parseint(substr(sha256("auto:auto:${var.name}:${g_name}"), 0, 8), 16) % 49000) + 1000
  }
}

resource "ravion_domain" "ravion_auto_label" {
  for_each = local.ravion_auto_label_pairs

  dns_provider_id             = var.ravion_dns_provider_id
  slug                        = each.value.slug
  parent_domain_allocation_id = var.ravion_parent_domain_allocation_id

  lifecycle {
    precondition {
      condition     = var.ravion_dns_provider_id != null && var.ravion_dns_provider_id != ""
      error_message = "ravion_dns_provider_id must be set when using ravion_auto certificate groups."
    }
  }
}

resource "ravion_domain" "ravion_auto_auto" {
  for_each = local.ravion_auto_auto_groups

  dns_provider_id             = var.ravion_dns_provider_id
  slug                        = var.module_instance_given_id
  parent_domain_allocation_id = var.ravion_parent_domain_allocation_id

  lifecycle {
    precondition {
      condition     = var.ravion_dns_provider_id != null && var.ravion_dns_provider_id != ""
      error_message = "ravion_dns_provider_id must be set when using ravion_auto certificate groups."
    }
  }
}

resource "aws_lb_listener_rule" "ravion_auto_label" {
  for_each = local.has_listener && local.has_target_group ? local.ravion_auto_label_pairs : {}

  listener_arn = var.listener_arn
  priority     = local.auto_label_priority[each.key]

  condition {
    host_header {
      values = [ravion_domain.ravion_auto_label[each.key].fqdn]
    }
  }

  action {
    type             = "forward"
    target_group_arn = var.target_group_arn
  }

  lifecycle {
    ignore_changes = [action]
  }

  tags = merge(var.tags, {
    "ravion:cert_group" = each.value.group_name
    "ravion:kind"       = "ravion_auto"
  })
}

resource "aws_lb_listener_rule" "ravion_auto_auto" {
  for_each = local.has_listener && local.has_target_group ? local.ravion_auto_auto_groups : {}

  listener_arn = var.listener_arn
  priority     = local.auto_auto_priority[each.key]

  condition {
    host_header {
      values = [ravion_domain.ravion_auto_auto[each.key].fqdn]
    }
  }

  action {
    type             = "forward"
    target_group_arn = var.target_group_arn
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
# 2. customer groups
################################################################################

locals {
  customer_groups = { for g in var.cert_groups : g.name => g if g.kind == "customer" }

  customer_pairs = merge([
    for g in var.cert_groups : {
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
    k => (parseint(substr(sha256("cust:${var.name}:${k}"), 0, 8), 16) % 49000) + 1000
  }
}

resource "ravion_domain" "customer" {
  for_each = local.customer_pairs

  dns_provider_id = local.customer_providers[each.value.group_name].id
  fqdn_override   = each.value.slug
}

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

resource "aws_lb_listener_certificate" "customer" {
  for_each = local.has_listener ? local.customer_groups : {}

  listener_arn    = var.listener_arn
  certificate_arn = aws_acm_certificate_validation.customer[each.key].certificate_arn
}

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
      dns_name = var.routing_target_dns_name
      zone_id  = var.routing_target_zone_id
    })
  }]
}

resource "aws_route53_record" "customer_routing_r53" {
  for_each = {
    for k, v in local.customer_pairs : k => v
    if local.customer_providers[v.group_name].route53 != null
  }

  zone_id = local.customer_providers[each.value.group_name].route53.hosted_zone_id
  name    = ravion_domain.customer[each.key].fqdn
  type    = "A"

  alias {
    name                   = var.routing_target_dns_name
    zone_id                = var.routing_target_zone_id
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
      dns_name = var.routing_target_dns_name
      zone_id  = var.routing_target_zone_id
    })
  }]
  depends_on = [aws_route53_record.customer_routing_r53]
}

resource "cloudflare_dns_record" "customer_routing_cf" {
  for_each = {
    for k, v in local.customer_pairs : k => v
    if local.customer_providers[v.group_name].cloudflare != null
  }

  zone_id = local.customer_providers[each.value.group_name].cloudflare.zone_id
  name    = ravion_domain.customer[each.key].fqdn
  type    = "CNAME"
  content = var.routing_target_dns_name
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
    value = var.routing_target_dns_name
    ttl   = 60
  }]
  depends_on = [cloudflare_dns_record.customer_routing_cf]
}

resource "aws_lb_listener_rule" "customer" {
  for_each = local.has_listener && local.has_target_group ? local.customer_pairs : {}

  listener_arn = var.listener_arn
  priority     = local.customer_priority_for_pair[each.key]

  condition {
    host_header {
      values = [ravion_domain.customer[each.key].fqdn]
    }
  }

  action {
    type             = "forward"
    target_group_arn = var.target_group_arn
  }

  lifecycle {
    ignore_changes = [action]
  }

  tags = merge(var.tags, {
    "ravion:cert_group" = each.value.group_name
    "ravion:kind"       = "customer"
  })
}
