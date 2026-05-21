################################################################################
# Parent-mode dispatch — issues ONE wildcard cert per group.
#
# Only active when var.mode == "parent". The cluster module uses this
# to create the wildcard cert(s) services nest under via cluster_inherit
# kind. NO listener rules + NO routing records — clusters don't route,
# they just attach the cert as SNI so the listener can serve it when a
# service FQDN comes in.
#
# Wildcard FQDN derivation:
#   kind=ravion_auto  → `<module_instance_id>-<random>.<platform_apex_domain>`
#                        (slug = stable hash of module_instance_id; suffix random)
#   kind=customer     → operator-typed wildcard_fqdn on the row
################################################################################

locals {
  parent_groups = var.mode == "parent" ? {
    for g in var.cert_groups : g.name => g
  } : {}

  parent_ravion_auto_groups = {
    for name, g in local.parent_groups : name => g if g.kind == "ravion_auto"
  }

  parent_customer_groups = {
    for name, g in local.parent_groups : name => g if g.kind == "customer"
  }
}

# 1a. ravion_auto parent allocation — slug derives from module_instance_id
# so two clusters in the same org can't collide on the auto allocation.
resource "ravion_domain" "parent_ravion_auto" {
  for_each = local.parent_ravion_auto_groups

  dns_provider_id = data.ravion_dns_provider.platform_apex[0].id
  slug            = var.module_instance_id

  lifecycle {
    precondition {
      condition     = var.module_instance_id != null && var.module_instance_id != ""
      error_message = "module_instance_id must be set when using ravion_auto parent cert groups."
    }
  }
}

# 1b. customer parent allocation — full FQDN typed by operator.
resource "ravion_domain" "parent_customer" {
  for_each = local.parent_customer_groups

  dns_provider_id = data.ravion_dns_provider.groups[each.key].id
  fqdn_override   = each.value.wildcard_fqdn

  lifecycle {
    precondition {
      condition     = each.value.wildcard_fqdn != null && each.value.wildcard_fqdn != ""
      error_message = "wildcard_fqdn must be set on customer parent cert groups."
    }
  }
}

# Unified per-group view for downstream resources — same shape whether
# the allocation came from ravion_auto or customer.
locals {
  parent_allocations = merge(
    { for name, alloc in ravion_domain.parent_ravion_auto : name => {
      id                = alloc.id
      managed_domain_id = alloc.managed_domain_id
      fqdn              = alloc.fqdn
      provider          = data.ravion_dns_provider.platform_apex[0]
    } },
    { for name, alloc in ravion_domain.parent_customer : name => {
      id                = alloc.id
      managed_domain_id = alloc.managed_domain_id
      fqdn              = alloc.fqdn
      provider          = data.ravion_dns_provider.groups[name]
    } },
  )
}

# 2. ONE wildcard ACM cert per parent group.
resource "aws_acm_certificate" "parent" {
  for_each = local.parent_allocations

  domain_name       = "*.${each.value.fqdn}"
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(var.tags, {
    "ravion:cert_group" = each.key
    "ravion:kind"       = "parent_wildcard"
  })
}

# 3. Validation pairs, flattened per provider variant.
locals {
  parent_validation_pairs = merge([
    for name, _alloc in local.parent_allocations : {
      for opt in aws_acm_certificate.parent[name].domain_validation_options :
      "${name}/${opt.domain_name}" => {
        group_name = name
        opt        = opt
        provider   = local.parent_allocations[name].provider
        domain_key = name
      }
    }
  ]...)

  parent_validation_pairs_route53_ravion = {
    for k, v in local.parent_validation_pairs : k => v
    if v.provider.route53_ravion != null
  }
  parent_validation_pairs_route53 = {
    for k, v in local.parent_validation_pairs : k => v
    if v.provider.route53 != null
  }
  parent_validation_pairs_cloudflare = {
    for k, v in local.parent_validation_pairs : k => v
    if v.provider.cloudflare != null
  }
}

# 4a. ROUTE53_RAVION validation — Ravion writes the record inline.
resource "ravion_dns_records" "parent_validation_ravion" {
  for_each = local.parent_validation_pairs_route53_ravion

  managed_domain_id = local.parent_allocations[each.value.group_name].managed_domain_id
  records = [{
    name  = each.value.opt.resource_record_name
    type  = each.value.opt.resource_record_type
    value = each.value.opt.resource_record_value
    ttl   = 60
  }]
}

# 4b. ROUTE53 customer validation.
resource "aws_route53_record" "parent_validation_r53" {
  for_each = local.parent_validation_pairs_route53

  zone_id = each.value.provider.route53.hosted_zone_id
  name    = each.value.opt.resource_record_name
  type    = each.value.opt.resource_record_type
  records = [each.value.opt.resource_record_value]
  ttl     = 60
}

resource "ravion_dns_records" "parent_validation_metadata_r53" {
  for_each = local.parent_validation_pairs_route53

  managed_domain_id = local.parent_allocations[each.value.group_name].managed_domain_id
  records = [{
    name  = each.value.opt.resource_record_name
    type  = each.value.opt.resource_record_type
    value = each.value.opt.resource_record_value
    ttl   = 60
  }]
  depends_on = [aws_route53_record.parent_validation_r53]
}

# 4c. CLOUDFLARE validation.
resource "cloudflare_dns_record" "parent_validation_cf" {
  for_each = local.parent_validation_pairs_cloudflare

  zone_id = each.value.provider.cloudflare.zone_id
  name    = trimsuffix(each.value.opt.resource_record_name, ".")
  type    = each.value.opt.resource_record_type
  content = trimsuffix(each.value.opt.resource_record_value, ".")
  ttl     = 60
  proxied = false
}

resource "ravion_dns_records" "parent_validation_metadata_cf" {
  for_each = local.parent_validation_pairs_cloudflare

  managed_domain_id = local.parent_allocations[each.value.group_name].managed_domain_id
  records = [{
    name  = each.value.opt.resource_record_name
    type  = each.value.opt.resource_record_type
    value = each.value.opt.resource_record_value
    ttl   = 60
  }]
  depends_on = [cloudflare_dns_record.parent_validation_cf]
}

# 5. Cert validation — waits for the right writer per variant.
resource "aws_acm_certificate_validation" "parent" {
  for_each = local.parent_allocations

  certificate_arn = aws_acm_certificate.parent[each.key].arn
  validation_record_fqdns = concat(
    [for k, v in local.parent_validation_pairs_route53_ravion : ravion_dns_records.parent_validation_ravion[k].fqdns[0] if v.group_name == each.key],
    [for k, v in local.parent_validation_pairs_route53 : ravion_dns_records.parent_validation_metadata_r53[k].fqdns[0] if v.group_name == each.key],
    [for k, v in local.parent_validation_pairs_cloudflare : ravion_dns_records.parent_validation_metadata_cf[k].fqdns[0] if v.group_name == each.key],
  )
}

# 6. Register cert metadata at Ravion.
resource "ravion_managed_certificate" "parent" {
  for_each = local.parent_allocations

  cert_arn           = aws_acm_certificate_validation.parent[each.key].certificate_arn
  status             = "ISSUED"
  scope              = "CLUSTER"
  managed_domain_ids = [each.value.managed_domain_id]
  issued_at          = aws_acm_certificate.parent[each.key].not_before
  expires_at         = aws_acm_certificate.parent[each.key].not_after
}

# SNI cert attachment is the PARENT MODULE's responsibility (cluster
# threads the ARN through its ALB child module's certificate_arns list
# so the cert can serve as default OR SNI without double-attach). The
# `parent_groups` output below exposes the ARN for that consumer.
