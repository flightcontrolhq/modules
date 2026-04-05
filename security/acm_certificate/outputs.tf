################################################################################
# Outputs
################################################################################

output "certificate_arn" {
  description = "The ARN of the ACM certificate."
  value       = aws_acm_certificate.this.arn
}

output "certificate_status" {
  description = "The validation status of the certificate (e.g. PENDING_VALIDATION, ISSUED)."
  value       = aws_acm_certificate.this.status
}

output "validation_records" {
  description = "DNS validation records (typically CNAME name, type, and value) required to issue the certificate."
  value = [
    for dvo in aws_acm_certificate.this.domain_validation_options : {
      domain_name = dvo.domain_name
      name        = dvo.resource_record_name
      type        = dvo.resource_record_type
      value       = dvo.resource_record_value
    }
  ]
}
