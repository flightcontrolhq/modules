################################################################################
# ACM Certificate
################################################################################

resource "aws_acm_certificate" "this" {
  domain_name               = var.domain_name
  subject_alternative_names = length(var.subject_alternative_names) > 0 ? var.subject_alternative_names : null
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(local.tags, {
    Name = "${var.name}-certificate"
  })
}

################################################################################
# Certificate validation (optional wait for ISSUED)
################################################################################

resource "aws_acm_certificate_validation" "this" {
  count = var.wait_for_validation ? 1 : 0

  certificate_arn = aws_acm_certificate.this.arn

  validation_record_fqdns = local.create_route53_records ? [for r in aws_route53_record.validation : r.fqdn] : [for dvo in aws_acm_certificate.this.domain_validation_options : dvo.resource_record_name]
}
