################################################################################
# Ravion domain control plane — cluster wildcard (V2)
#
# Allocates `*.<cluster-fqdn>` under the registered DnsProvider's apex
# and issues a wildcard ACM cert covering it. Service modules under
# this cluster create child allocations whose FQDNs sit under
# <cluster-fqdn>, so they inherit the wildcard cert via SNI without
# their own ACM work.
#
# Variant dispatch (count = local.is_X ? 1 : 0):
#   ROUTE53_RAVION → Ravion's own Route53. RavionRoute53Writer issues
#                    the ChangeResourceRecordSets call inline.
#   ROUTE53        → Customer's Route53. Customer's `aws_route53_record`
#                    in their AWS account writes the record; Ravion
#                    persists metadata via `ravion_dns_records` after-
#                    the-fact (depends_on).
#   CLOUDFLARE     → Customer's Cloudflare zone. `cloudflare_dns_record`
#                    writes the record using the api_token 

#   EXTERNAL       → Skipped — module assumes BYO cert in this mode.
#
# All AWS / Cloudflare resources live in the customer's accounts,
# applied by their TF runner with their IAM. Ravion never holds
# customer credentials.
################################################################################

# ---- 1. Allocate the cluster's wildcard FQDN -------------------------------
# Single ravion_domain resource regardless of variant — the API knows
# which provider it lives under from dns_provider_id.
resource "ravion_domain" "cluster" {
  count           = local.enable_ravion_domain ? 1 : 0
  dns_provider_id = local.dns_provider.id
  # Auto-mode (use_ravion_subdomain + module_instance_id known) posts
  # the literal `<module-instance-id>.<apex>` so the wildcard cert
  # covers `*.<module-instance-id>.<apex>`. Slug mode falls back to
  # the legacy `<slug>-<hash>.<apex>` derivation.
  slug          = local.cluster_auto_fqdn == null ? coalesce(var.ravion_cluster_slug, var.name) : null
  fqdn_override = local.cluster_auto_fqdn
  wildcard      = true
}

# ---- 2. ACM wildcard cert (skipped for EXTERNAL) ---------------------------
resource "aws_acm_certificate" "cluster" {
  count = local.enable_acm_cert ? 1 : 0

  domain_name       = ravion_domain.cluster[0].fqdn
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = var.tags
}

# ---- 3a. ROUTE53_RAVION validation records ---------------------------------
# Synchronous — the RavionRoute53Writer issues a Route53
# ChangeResourceRecordSets call inline with our POST and returns when
# AWS accepts the change. No customer-side resources needed.
resource "ravion_dns_records" "cluster_validation_ravion" {
  count             = local.is_route53_ravion ? 1 : 0
  managed_domain_id = ravion_domain.cluster[0].id
  records = [
    for opt in aws_acm_certificate.cluster[0].domain_validation_options : {
      name  = opt.resource_record_name
      type  = opt.resource_record_type
      value = opt.resource_record_value
      ttl   = 60
    }
  ]
}

# ---- 3b. ROUTE53 (customer-owned) validation records -----------------------
# Customer's AWS account, customer's IAM. The for_each fan-out per
# validation option is the customer's actual write; the
# `ravion_dns_records.cluster_validation_metadata_r53` block below
# depends_on this so Ravion's metadata row lands after the record is
# live.
resource "aws_route53_record" "cluster_validation_r53" {
  for_each = local.is_route53 ? {
    for opt in aws_acm_certificate.cluster[0].domain_validation_options : opt.domain_name => opt
  } : {}

  zone_id = local.dns_provider.route53.hosted_zone_id
  name    = each.value.resource_record_name
  type    = each.value.resource_record_type
  records = [each.value.resource_record_value]
  ttl     = 60
}

resource "ravion_dns_records" "cluster_validation_metadata_r53" {
  count             = local.is_route53 ? 1 : 0
  managed_domain_id = ravion_domain.cluster[0].id
  records = [
    for opt in aws_acm_certificate.cluster[0].domain_validation_options : {
      name  = opt.resource_record_name
      type  = opt.resource_record_type
      value = opt.resource_record_value
      ttl   = 60
    }
  ]
  depends_on = [aws_route53_record.cluster_validation_r53]
}

# ---- 3c. CLOUDFLARE validation records -------------------------------------
# Customer's Cloudflare zone. The cloudflare provider's api_token is
# resolved by data.ravion_dns_provider — see
# provider.tf for the provider block.
resource "cloudflare_dns_record" "cluster_validation_cf" {
  for_each = local.is_cloudflare ? {
    for opt in aws_acm_certificate.cluster[0].domain_validation_options : opt.domain_name => opt
  } : {}

  zone_id = local.dns_provider.cloudflare.zone_id
  name    = trimsuffix(each.value.resource_record_name, ".")
  type    = each.value.resource_record_type
  content = trimsuffix(each.value.resource_record_value, ".")
  ttl     = 60
  proxied = false
}

resource "ravion_dns_records" "cluster_validation_metadata_cf" {
  count             = local.is_cloudflare ? 1 : 0
  managed_domain_id = ravion_domain.cluster[0].id
  records = [
    for opt in aws_acm_certificate.cluster[0].domain_validation_options : {
      name  = opt.resource_record_name
      type  = opt.resource_record_type
      value = opt.resource_record_value
      ttl   = 60
    }
  ]
  depends_on = [cloudflare_dns_record.cluster_validation_cf]
}

# ---- 4a. ROUTE53_RAVION apex routing record -------------------------------
# Wildcard FQDN points at the cluster's public ALB. ALIAS works because
# Route53 supports apex-style routing.
resource "ravion_dns_records" "cluster_routing_ravion" {
  count             = local.is_route53_ravion && var.enable_public_alb ? 1 : 0
  managed_domain_id = ravion_domain.cluster[0].id
  records = [{
    name = ravion_domain.cluster[0].fqdn
    type = "ALIAS"
    value = jsonencode({
      dns_name = module.public_alb[0].alb_dns_name
      zone_id  = module.public_alb[0].alb_zone_id
    })
  }]
}

# ---- 4b. ROUTE53 (customer) apex routing record ---------------------------
# AWS A-record alias targeting the cluster's ALB. Customer's IAM
# writes it; Ravion records metadata.
resource "aws_route53_record" "cluster_routing_r53" {
  count = local.is_route53 && var.enable_public_alb ? 1 : 0

  zone_id = local.dns_provider.route53.hosted_zone_id
  name    = ravion_domain.cluster[0].fqdn
  type    = "A"

  alias {
    name                   = module.public_alb[0].alb_dns_name
    zone_id                = module.public_alb[0].alb_zone_id
    evaluate_target_health = true
  }
}

resource "ravion_dns_records" "cluster_routing_metadata_r53" {
  count             = local.is_route53 && var.enable_public_alb ? 1 : 0
  managed_domain_id = ravion_domain.cluster[0].id
  records = [{
    name = ravion_domain.cluster[0].fqdn
    type = "ALIAS"
    value = jsonencode({
      dns_name = module.public_alb[0].alb_dns_name
      zone_id  = module.public_alb[0].alb_zone_id
    })
  }]
  depends_on = [aws_route53_record.cluster_routing_r53]
}

# ---- 4c. CLOUDFLARE apex routing record -----------------------------------
# Cloudflare doesn't do AWS ALIAS records. A CNAME at the wildcard
# apex pointing at the ALB DNS name is functionally equivalent here
# (the cluster FQDN is `<slug>-<hash>.<apex>`, not the apex itself —
# CNAMEs at non-apex labels are allowed).
resource "cloudflare_dns_record" "cluster_routing_cf" {
  count = local.is_cloudflare && var.enable_public_alb ? 1 : 0

  zone_id = local.dns_provider.cloudflare.zone_id
  name    = ravion_domain.cluster[0].fqdn
  type    = "CNAME"
  content = module.public_alb[0].alb_dns_name
  ttl     = 60
  proxied = false
}

resource "ravion_dns_records" "cluster_routing_metadata_cf" {
  count             = local.is_cloudflare && var.enable_public_alb ? 1 : 0
  managed_domain_id = ravion_domain.cluster[0].id
  records = [{
    name  = ravion_domain.cluster[0].fqdn
    type  = "CNAME"
    value = module.public_alb[0].alb_dns_name
    ttl   = 60
  }]
  depends_on = [cloudflare_dns_record.cluster_routing_cf]
}

# ---- 5. Block until ACM has validated the cert ----------------------------
# Pulls validation_record_fqdns from whichever ravion_dns_records
# branch fired. Only one is non-null in any given plan; the
# alternative branches return empty lists. concat() flattens.
resource "aws_acm_certificate_validation" "cluster" {
  count           = local.enable_acm_cert ? 1 : 0
  certificate_arn = aws_acm_certificate.cluster[0].arn
  validation_record_fqdns = concat(
    local.is_route53_ravion ? ravion_dns_records.cluster_validation_ravion[0].fqdns : [],
    local.is_route53 ? ravion_dns_records.cluster_validation_metadata_r53[0].fqdns : [],
    local.is_cloudflare ? ravion_dns_records.cluster_validation_metadata_cf[0].fqdns : [],
  )
}

# ---- 6. Register cert metadata at Ravion ----------------------------------
# Same for every variant — the UI cares about cert status, not where
# the validation records live.
resource "ravion_managed_certificate" "cluster" {
  count              = local.enable_acm_cert ? 1 : 0
  cert_arn           = aws_acm_certificate_validation.cluster[0].certificate_arn
  status             = "ISSUED"
  scope              = "CLUSTER_WILDCARD"
  managed_domain_ids = [ravion_domain.cluster[0].managed_domain_id]
  issued_at          = aws_acm_certificate.cluster[0].not_before
  expires_at         = aws_acm_certificate.cluster[0].not_after
}
