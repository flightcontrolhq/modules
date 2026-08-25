################################################################################
# Wildcard certificate for *.sbx.<env>.<domain>
#
# One cert covers every sandbox hostname, because hostnames are minted per
# request and no per-sandbox certificate could ever be issued in time.
################################################################################

resource "aws_acm_certificate" "wildcard" {
  domain_name               = local.wildcard_domain
  subject_alternative_names = [local.ingress_domain]
  validation_method         = "DNS"

  # Named for the apex, not the wildcard: an AWS tag value may not contain `*`,
  # so `Name = local.wildcard_domain` is rejected at create time. The certificate
  # still covers `*.sbx.<env>.<domain>` — that is `domain_name` above.
  tags = merge(local.tags, { Name = local.ingress_domain })

  lifecycle {
    create_before_destroy = true
  }
}

# When the zone is ours, validation is a pair of records and a short wait.
resource "aws_route53_record" "acm_validation" {
  for_each = local.create_dns ? {
    for dvo in aws_acm_certificate.wildcard.domain_validation_options :
    dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  } : {}

  zone_id         = var.ingress.hosted_zone_id
  name            = each.value.name
  type            = each.value.type
  records         = [each.value.record]
  ttl             = 60
  allow_overwrite = true
}

# The wait exists in both cases. With an external zone there are no records for
# Terraform to create, so the apply parks here until the operator adds the two
# records this module reports (`acm_validation_records`, and the same pair is
# visible in the plan). A listener cannot attach a PENDING_VALIDATION
# certificate, so there is nothing useful to do before that happens.
resource "aws_acm_certificate_validation" "wildcard" {
  count = var.wait_for_certificate_validation ? 1 : 0

  certificate_arn         = aws_acm_certificate.wildcard.arn
  validation_record_fqdns = local.create_dns ? [for r in aws_route53_record.acm_validation : r.fqdn] : null

  timeouts {
    create = var.acm_validation_timeout
  }
}
