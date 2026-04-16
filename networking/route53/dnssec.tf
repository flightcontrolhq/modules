################################################################################
# DNSSEC
################################################################################

resource "aws_route53_key_signing_key" "this" {
  count = var.enable_dnssec ? 1 : 0

  name                       = "${coalesce(var.name, local.zone_id)}-ksk"
  hosted_zone_id             = local.zone_id
  key_management_service_arn = var.dnssec_kms_key_arn
  status                     = var.dnssec_signing_status == "SIGNING" ? "ACTIVE" : "INACTIVE"

  lifecycle {
    precondition {
      condition     = var.dnssec_kms_key_arn != null
      error_message = "dnssec_kms_key_arn is required when enable_dnssec is true."
    }
  }
}

resource "aws_route53_hosted_zone_dnssec" "this" {
  count = var.enable_dnssec ? 1 : 0

  hosted_zone_id = aws_route53_key_signing_key.this[0].hosted_zone_id
  signing_status = var.dnssec_signing_status
}
