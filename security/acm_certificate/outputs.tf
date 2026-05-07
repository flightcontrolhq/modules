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

################################################################################
# Account & Region
################################################################################

output "aws_account_id" {
  description = "The AWS account ID where the resources are deployed."
  value       = data.aws_caller_identity.current.account_id
}

output "region" {
  description = "The AWS region where the resources are deployed."
  value       = local.region
}
