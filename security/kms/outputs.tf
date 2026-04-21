################################################################################
# Outputs
################################################################################

output "key_id" {
  description = "The KMS key UUID."
  value       = aws_kms_key.this.key_id
}

output "key_arn" {
  description = "The KMS key ARN. Use as the Resource in IAM role policies that grant cryptographic operations on this key."
  value       = aws_kms_key.this.arn
}

output "alias_name" {
  description = "The KMS alias name (alias/<name>). Stable identifier across rotations — downstream consumers should reference the alias rather than the key UUID where possible."
  value       = aws_kms_alias.this.name
}

output "alias_arn" {
  description = "The KMS alias ARN."
  value       = aws_kms_alias.this.arn
}

output "key_spec" {
  description = "The cryptographic key spec the key was created with (echoes var.key_spec)."
  value       = aws_kms_key.this.customer_master_key_spec
}

output "key_usage" {
  description = "The intended use of the key (echoes var.key_usage)."
  value       = aws_kms_key.this.key_usage
}
