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
#   external — Customer owns BOTH DNS and TLS material end-to-end.
#     Ravion records the FQDN (so it shows on the Domains tab) and
#     wires a host-header listener rule, but writes ZERO DNS records
#     and provisions ZERO ACM cert. Customer's reverse-proxy / Cloudflare
#     Tunnel / etc. is responsible for terminating TLS and pointing at
#     var.routing_target_dns_name. Resolves the synthetic per-org
#     EXTERNAL DnsProvider (looked up via data source by provider_type).
#
# Listener-rule priorities use a 32-bit sha256-derived bucket index
# modulo 49000 (ALB priority range 1000..50000). Per-kind seed prefix
# prevents collisions across kinds within the same listener.
################################################################################

locals {
  has_listener     = var.listener_arn != null && var.listener_arn != ""
  has_target_group = var.target_group_arn != null && var.target_group_arn != ""
  cluster_managed  = var.ravion_parent_domain_allocation_id != null && var.ravion_parent_domain_allocation_id != ""
  leaf_mode        = var.mode == "leaf"
}

################################################################################
# 1. inherit groups — leaf labels under a chosen cluster
#    parent group (issued by the upstream cluster's parent-mode block).
#    No own cert; inherits the cluster wildcard via SNI.
#
# Domain semantics:
#   non-empty `domains` — each entry is a leaf label; allocation is
#                         `<label>-<hash>.<cluster.wildcard_fqdn>`.
#   empty `domains`     — ONE zero-typing auto-allocation using
#                         module_instance_given_id as the slug.
################################################################################

locals {
  inherit_groups = local.leaf_mode ? {
    for g in var.cert_groups :
    g.name => g if g.kind == "inherit" && contains(keys(var.cluster_groups), coalesce(g.parent_group_name, ""))
  } : {}

  inherit_label_pairs = merge([
    for g_name, g in local.inherit_groups : {
      for d in g.domains : "${g_name}/${d}" => {
        group_name         = g_name
        slug               = d
        parent_group_name = g.parent_group_name
      }
    }
  ]...)

  inherit_auto_groups = {
    for g_name, g in local.inherit_groups :
    g_name => g
    if length(g.domains) == 0
    && var.module_instance_given_id != null
    && var.module_instance_given_id != ""
  }

  cw_label_priority = {
    for k, _v in local.inherit_label_pairs :
    k => (parseint(substr(sha256("cw:${var.name}:${k}"), 0, 8), 16) % 49000) + 1000
  }
  cw_auto_priority = {
    for g_name, _v in local.inherit_auto_groups :
    g_name => (parseint(substr(sha256("cw:auto:${var.name}:${g_name}"), 0, 8), 16) % 49000) + 1000
  }
}

# 1a. Per-leaf allocation, nested under the chosen cluster parent group.
resource "ravion_domain" "inherit_label" {
  for_each = local.inherit_label_pairs

  dns_provider_id             = var.cluster_groups[each.value.parent_group_name].dns_provider_id
  slug                        = each.value.slug
  parent_domain_allocation_id = var.cluster_groups[each.value.parent_group_name].parent_allocation_id
}

# 1b. Zero-typing auto allocation per group when `domains` is empty.
resource "ravion_domain" "inherit_auto" {
  for_each = local.inherit_auto_groups

  dns_provider_id             = var.cluster_groups[each.value.parent_group_name].dns_provider_id
  slug                        = var.module_instance_given_id
  parent_domain_allocation_id = var.cluster_groups[each.value.parent_group_name].parent_allocation_id
}

resource "aws_lb_listener_rule" "inherit_label" {
  for_each = local.inherit_label_pairs

  listener_arn = var.listener_arn
  priority     = local.cw_label_priority[each.key]

  condition {
    host_header {
      values = [ravion_domain.inherit_label[each.key].fqdn]
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
    "ravion:kind"       = "inherit"
  })
}

resource "aws_lb_listener_rule" "inherit_auto" {
  for_each = local.inherit_auto_groups

  listener_arn = var.listener_arn
  priority     = local.cw_auto_priority[each.key]

  condition {
    host_header {
      values = [ravion_domain.inherit_auto[each.key].fqdn]
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
    "ravion:kind"       = "inherit"
  })
}

################################################################################
# 2. customer groups
################################################################################

locals {
  customer_groups = local.leaf_mode ? { for g in var.cert_groups : g.name => g if g.kind == "customer" } : {}

  customer_pairs = local.leaf_mode ? merge([
    for g in var.cert_groups : {
      for d in g.domains : "${g.name}/${d}" => {
        group_name = g.name
        slug       = d
      }
    }
    if g.kind == "customer"
  ]...) : {}

  customer_providers = {
    for name, _g in local.customer_groups :
    name => data.ravion_dns_provider.groups[name]
  }

  # Non-sensitive provider kind dispatch. data.ravion_dns_provider's
  # cloudflare.api_token is marked Sensitive; ANY value derived from
  # the provider attribute group inherits sensitivity, which Terraform
  # then refuses inside for_each keys + filter conditions. nonsensitive()
  # is safe here because the string result encodes only the discriminator
  # (no secret payload).
  customer_provider_kind = {
    for name, _g in local.customer_groups :
    name => nonsensitive(
      data.ravion_dns_provider.groups[name].route53_ravion != null ? "route53_ravion" :
      data.ravion_dns_provider.groups[name].route53 != null ? "route53" :
      data.ravion_dns_provider.groups[name].cloudflare != null ? "cloudflare" :
      "external"
    )
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
  # Static (group, domain) keys — known at plan, identical to
  # customer_pairs. The per-domain validation option is resolved
  # inside each resource body via a list-filter on
  # `aws_acm_certificate.customer[cert_key].domain_validation_options`
  # so the for_each keys stay statically determinable even though the
  # validation values land only post-cert-issuance.
  customer_validation_pairs = local.customer_pairs

  customer_validation_pairs_route53_ravion = {
    for k, v in local.customer_validation_pairs : k => v
    if local.customer_provider_kind[v.group_name] == "route53_ravion"
  }
  customer_validation_pairs_route53 = {
    for k, v in local.customer_validation_pairs : k => v
    if local.customer_provider_kind[v.group_name] == "route53"
  }
  customer_validation_pairs_cloudflare = {
    for k, v in local.customer_validation_pairs : k => v
    if local.customer_provider_kind[v.group_name] == "cloudflare"
  }
}

resource "ravion_dns_records" "customer_validation_ravion" {
  for_each = local.customer_validation_pairs_route53_ravion

  managed_domain_id = ravion_domain.customer[each.key].id
  records = [
    for opt in aws_acm_certificate.customer[each.value.group_name].domain_validation_options : {
      name  = opt.resource_record_name
      type  = opt.resource_record_type
      value = opt.resource_record_value
      ttl   = 60
    }
    if opt.domain_name == ravion_domain.customer[each.key].fqdn
  ]
}

resource "aws_route53_record" "customer_validation_r53" {
  for_each = local.customer_validation_pairs_route53

  zone_id = local.customer_providers[each.value.group_name].route53.hosted_zone_id
  name    = [
    for opt in aws_acm_certificate.customer[each.value.group_name].domain_validation_options :
    opt.resource_record_name
    if opt.domain_name == ravion_domain.customer[each.key].fqdn
  ][0]
  type    = [
    for opt in aws_acm_certificate.customer[each.value.group_name].domain_validation_options :
    opt.resource_record_type
    if opt.domain_name == ravion_domain.customer[each.key].fqdn
  ][0]
  records = [
    for opt in aws_acm_certificate.customer[each.value.group_name].domain_validation_options :
    opt.resource_record_value
    if opt.domain_name == ravion_domain.customer[each.key].fqdn
  ]
  ttl = 60
}

resource "ravion_dns_records" "customer_validation_metadata_r53" {
  for_each = local.customer_validation_pairs_route53

  managed_domain_id = ravion_domain.customer[each.key].id
  records = [
    for opt in aws_acm_certificate.customer[each.value.group_name].domain_validation_options : {
      name  = opt.resource_record_name
      type  = opt.resource_record_type
      value = opt.resource_record_value
      ttl   = 60
    }
    if opt.domain_name == ravion_domain.customer[each.key].fqdn
  ]
  depends_on = [aws_route53_record.customer_validation_r53]
}

# Cloudflare validation records — single SDK-backed write. The
# api-go CloudflareWriter resolves the customer's api_token from
# vault and calls cloudflare-go's DNS API directly.
resource "ravion_dns_records" "customer_validation_cf" {
  for_each = local.customer_validation_pairs_cloudflare

  managed_domain_id = ravion_domain.customer[each.key].id
  records = [
    for opt in aws_acm_certificate.customer[each.value.group_name].domain_validation_options : {
      name  = opt.resource_record_name
      type  = opt.resource_record_type
      value = opt.resource_record_value
      ttl   = 60
    }
    if opt.domain_name == ravion_domain.customer[each.key].fqdn
  ]
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
      for k, v in local.customer_validation_pairs_cloudflare : ravion_dns_records.customer_validation_cf[k].fqdns[0]
      if v.group_name == each.key
    ],
  )
}

resource "ravion_managed_certificate" "customer" {
  for_each = local.customer_groups

  cert_arn = aws_acm_certificate_validation.customer[each.key].certificate_arn
  status   = "ISSUED"
  scope    = "LEAF"
  name     = each.key
  kind     = "customer"
  managed_domain_ids = [
    for d in each.value.domains :
    ravion_domain.customer["${each.key}/${d}"].managed_domain_id
  ]
  issued_at  = aws_acm_certificate.customer[each.key].not_before
  expires_at = aws_acm_certificate.customer[each.key].not_after
}

resource "aws_lb_listener_certificate" "customer" {
  for_each = local.customer_groups

  listener_arn    = var.listener_arn
  certificate_arn = aws_acm_certificate_validation.customer[each.key].certificate_arn
}

resource "ravion_dns_records" "customer_routing_ravion" {
  for_each = {
    for k, v in local.customer_pairs : k => v
    if local.customer_provider_kind[v.group_name] == "route53_ravion"
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
    if local.customer_provider_kind[v.group_name] == "route53"
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
    if local.customer_provider_kind[v.group_name] == "route53"
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

resource "ravion_dns_records" "customer_routing_cf" {
  for_each = {
    for k, v in local.customer_pairs : k => v
    if local.customer_provider_kind[v.group_name] == "cloudflare"
  }

  managed_domain_id = ravion_domain.customer[each.key].id
  records = [{
    name  = ravion_domain.customer[each.key].fqdn
    type  = "CNAME"
    value = var.routing_target_dns_name
    ttl   = 60
  }]
}

resource "aws_lb_listener_rule" "customer" {
  for_each = local.customer_pairs

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

################################################################################
# 3. external groups — customer owns DNS + TLS end-to-end.
#
# Metadata-only: emit a ravion_domain row (so the FQDN appears on the
# Domains tab) and add a host-header listener rule so the ALB routes
# matching traffic to the target group. Ravion writes ZERO DNS records
# and provisions ZERO ACM cert — the customer is expected to either
# bring a wildcard already attached to the listener, terminate TLS in
# front of the ALB themselves, or accept HTTPS errors until they
# attach their own cert out-of-band.
################################################################################

locals {
  external_groups = local.leaf_mode ? { for g in var.cert_groups : g.name => g if g.kind == "external" } : {}

  external_pairs = local.leaf_mode ? merge([
    for g in var.cert_groups : {
      for d in g.domains : "${g.name}/${d}" => {
        group_name = g.name
        slug       = d
      }
    }
    if g.kind == "external"
  ]...) : {}

  external_priority_for_pair = {
    for k, _v in local.external_pairs :
    k => (parseint(substr(sha256("ext:${var.name}:${k}"), 0, 8), 16) % 49000) + 1000
  }

  has_external = length(local.external_pairs) > 0
}

data "ravion_dns_provider" "external" {
  count    = local.has_external ? 1 : 0
  given_id = var.external_dns_provider_given_id
}

resource "ravion_domain" "external" {
  for_each = local.external_pairs

  dns_provider_id = data.ravion_dns_provider.external[0].id
  fqdn_override   = each.value.slug
}

resource "aws_lb_listener_rule" "external" {
  for_each = local.external_pairs

  listener_arn = var.listener_arn
  priority     = local.external_priority_for_pair[each.key]

  condition {
    host_header {
      values = [ravion_domain.external[each.key].fqdn]
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
    "ravion:kind"       = "external"
  })
}

# Placeholder ravion_managed_certificate per external group — anchors
# the cert-group identity for the Domains-tab projector (one MCert
# row IS one cert group). Ravion provisions NO ACM cert here; the
# synthetic `external:` ARN gives the unique key its uniqueness and
# the status stays PENDING for the row's lifetime.
resource "ravion_managed_certificate" "external" {
  for_each = local.external_groups

  cert_arn = "external:${var.name}:${each.key}"
  status   = "PENDING"
  scope    = "CUSTOM_DOMAIN"
  name     = each.key
  kind     = "external"
  managed_domain_ids = [
    for d in each.value.domains :
    ravion_domain.external["${each.key}/${d}"].managed_domain_id
  ]
}

################################################################################
# 4. inherit-group placeholder certs.
#
# Inherit groups SNI-share the parent cluster's wildcard cert via the
# parent_allocation chain — they don't issue their own. To anchor the
# cert-group identity on the Domains tab (one ManagedCertificate IS
# one cert group), we emit a placeholder ravion_managed_certificate
# per group with a synthetic `inherit:` ARN.
################################################################################

resource "ravion_managed_certificate" "inherit" {
  for_each = local.inherit_groups

  cert_arn = "inherit:${var.name}:${each.key}"
  status   = "ISSUED"
  scope    = "WILDCARD"
  name     = each.key
  kind     = "inherit"
  managed_domain_ids = concat(
    [
      for d in each.value.domains :
      ravion_domain.inherit_label["${each.key}/${d}"].managed_domain_id
    ],
    contains(keys(local.inherit_auto_groups), each.key)
      ? [ravion_domain.inherit_auto[each.key].managed_domain_id]
      : [],
  )
}
