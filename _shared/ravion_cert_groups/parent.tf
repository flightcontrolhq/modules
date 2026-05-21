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

# 3. Per-group variant subsets. Keys are group names (KNOWN at plan
# time); values include the cert (needed for domain_validation_options
# which is only known after apply). Iterating these maps means TF can
# plan the resource set without resolving the cert's validation list.
locals {
  parent_groups_route53_ravion = {
    for name, alloc in local.parent_allocations : name => alloc
    if alloc.provider.route53_ravion != null
  }
  parent_groups_route53 = {
    for name, alloc in local.parent_allocations : name => alloc
    if alloc.provider.route53 != null
  }
  parent_groups_cloudflare = {
    for name, alloc in local.parent_allocations : name => alloc
    if alloc.provider.cloudflare != null
  }
}

# 4a. ROUTE53_RAVION validation — Ravion writes the record inline.
# Wildcard parent certs have one validation per cert; we grab [0].
resource "ravion_dns_records" "parent_validation_ravion" {
  for_each = local.parent_groups_route53_ravion

  managed_domain_id = each.value.id
  records = [{
    name  = tolist(aws_acm_certificate.parent[each.key].domain_validation_options)[0].resource_record_name
    type  = tolist(aws_acm_certificate.parent[each.key].domain_validation_options)[0].resource_record_type
    value = tolist(aws_acm_certificate.parent[each.key].domain_validation_options)[0].resource_record_value
    ttl   = 60
  }]
}

# 4b. ROUTE53 customer validation.
resource "aws_route53_record" "parent_validation_r53" {
  for_each = local.parent_groups_route53

  zone_id = each.value.provider.route53.hosted_zone_id
  name    = tolist(aws_acm_certificate.parent[each.key].domain_validation_options)[0].resource_record_name
  type    = tolist(aws_acm_certificate.parent[each.key].domain_validation_options)[0].resource_record_type
  records = [tolist(aws_acm_certificate.parent[each.key].domain_validation_options)[0].resource_record_value]
  ttl     = 60
}

resource "ravion_dns_records" "parent_validation_metadata_r53" {
  for_each = local.parent_groups_route53

  managed_domain_id = each.value.id
  records = [{
    name  = tolist(aws_acm_certificate.parent[each.key].domain_validation_options)[0].resource_record_name
    type  = tolist(aws_acm_certificate.parent[each.key].domain_validation_options)[0].resource_record_type
    value = tolist(aws_acm_certificate.parent[each.key].domain_validation_options)[0].resource_record_value
    ttl   = 60
  }]
  depends_on = [aws_route53_record.parent_validation_r53]
}

# 4c. CLOUDFLARE validation — single SDK-backed write via the api-go
# CloudflareWriter (cloudflare-go/v6, token from vault per call).
resource "ravion_dns_records" "parent_validation_cf" {
  for_each = local.parent_groups_cloudflare

  managed_domain_id = each.value.id
  records = [{
    name  = tolist(aws_acm_certificate.parent[each.key].domain_validation_options)[0].resource_record_name
    type  = tolist(aws_acm_certificate.parent[each.key].domain_validation_options)[0].resource_record_type
    value = tolist(aws_acm_certificate.parent[each.key].domain_validation_options)[0].resource_record_value
    ttl   = 60
  }]
}

# 5. Cert validation — waits for the right writer per variant.
resource "aws_acm_certificate_validation" "parent" {
  for_each = local.parent_allocations

  certificate_arn = aws_acm_certificate.parent[each.key].arn
  validation_record_fqdns = concat(
    contains(keys(local.parent_groups_route53_ravion), each.key) ? [ravion_dns_records.parent_validation_ravion[each.key].fqdns[0]] : [],
    contains(keys(local.parent_groups_route53), each.key) ? [ravion_dns_records.parent_validation_metadata_r53[each.key].fqdns[0]] : [],
    contains(keys(local.parent_groups_cloudflare), each.key) ? [ravion_dns_records.parent_validation_cf[each.key].fqdns[0]] : [],
  )
}

# 6. Register cert metadata at Ravion.
resource "ravion_managed_certificate" "parent" {
  for_each = local.parent_allocations

  cert_arn           = aws_acm_certificate_validation.parent[each.key].certificate_arn
  status             = "ISSUED"
  scope              = "CLUSTER_WILDCARD"
  managed_domain_ids = [each.value.managed_domain_id]
  issued_at          = aws_acm_certificate.parent[each.key].not_before
  expires_at         = aws_acm_certificate.parent[each.key].not_after
}

# SNI cert attachment is the PARENT MODULE's responsibility (cluster
# threads the ARN through its ALB child module's certificate_arns list
# so the cert can serve as default OR SNI without double-attach). The
# `parent_groups` output below exposes the ARN for that consumer.
