################################################################################
# Ravion-domain auto-allocation
#
# Opt-in via `var.ravion_dns_provider_id`. When set, this file:
#   1. Allocates one FQDN under the chosen DnsProvider (typically the
#      platform apex for "auto-generate on platform apex" callers).
#   2. Requests an ACM cert in us-east-1 for that FQDN
#      (CloudFront viewer certs MUST be us-east-1).
#   3. Publishes the ACM DNS-01 validation records via `ravion_dns_records`.
#   4. Blocks on `aws_acm_certificate_validation` so the cert ARN we
#      hand to CloudFront is guaranteed ISSUED.
#   5. Publishes the routing record (ALIAS → CloudFront) via
#      `ravion_dns_records`.
#   6. Registers the cert in the Ravion domain control plane via
#      `ravion_managed_certificate` so the Domains tab shows the cert
#      against the allocation.
#
# The CloudFront alias + cert attachment happens in `locals.tf` via
# `effective_distributions`, which merges these computed values into
# `var.distributions[var.ravion_attach_distribution_key]`.
#
# When `var.ravion_dns_provider_id` is null, every resource here has
# count = 0 and the module reverts to today's behavior (caller-supplied
# aliases/cert ARN on the distributions input).
################################################################################

resource "ravion_domain" "this" {
  count = local.use_ravion_domain ? 1 : 0

  dns_provider_id = var.ravion_dns_provider_id
  slug            = local.ravion_slug
}

resource "aws_acm_certificate" "ravion" {
  count = local.use_ravion_domain ? 1 : 0

  provider = aws.us_east_1

  domain_name       = ravion_domain.this[0].fqdn
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = local.tags
}

resource "ravion_dns_records" "ravion_validation" {
  count = local.use_ravion_domain ? 1 : 0

  managed_domain_id = ravion_domain.this[0].id
  # NOTE: `purpose` is unsupported on the currently-published v2.4.0
  # provider — re-add once the mirror serves a build that includes the
  # field on `ravion_dns_records`.

  records = [
    for o in aws_acm_certificate.ravion[0].domain_validation_options : {
      name  = trimsuffix(o.resource_record_name, ".")
      type  = o.resource_record_type
      value = trimsuffix(o.resource_record_value, ".")
      ttl   = 60
    }
  ]
}

resource "aws_acm_certificate_validation" "ravion" {
  count = local.use_ravion_domain ? 1 : 0

  provider = aws.us_east_1

  certificate_arn         = aws_acm_certificate.ravion[0].arn
  validation_record_fqdns = ravion_dns_records.ravion_validation[0].fqdns
}

# Routing record: ALIAS the allocated FQDN at the CloudFront
# distribution this module just attached the cert to. The distribution
# domain + hosted-zone id come from `module.cdn` outputs.
resource "ravion_dns_records" "ravion_routing" {
  count = local.use_ravion_domain ? 1 : 0

  managed_domain_id = ravion_domain.this[0].id
  # See note above on `purpose` — re-add when the published provider supports it.

  records = [{
    name = ravion_domain.this[0].fqdn
    type = "ALIAS"
    value = jsonencode({
      dns_name = module.cdn.distribution_domain_names[local.ravion_attach_key]
      zone_id  = module.cdn.distribution_hosted_zone_ids[local.ravion_attach_key]
    })
  }]
}

resource "ravion_managed_certificate" "ravion" {
  count = local.use_ravion_domain ? 1 : 0

  cert_arn  = aws_acm_certificate_validation.ravion[0].certificate_arn
  status    = "ISSUED"
  pattern   = "EXACT"
  ownership = "PLATFORM"

  managed_domain_ids = [ravion_domain.this[0].managed_domain_id]
  name               = local.ravion_cert_group_name
  kind               = "ravion_auto"

  issued_at  = aws_acm_certificate.ravion[0].not_before
  expires_at = aws_acm_certificate.ravion[0].not_after
}
