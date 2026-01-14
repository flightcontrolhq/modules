################################################################################
# S3 Bucket
################################################################################

output "bucket_id" {
  description = "The name of the S3 bucket."
  value       = aws_s3_bucket.this.id
}

output "bucket_arn" {
  description = "The ARN of the S3 bucket."
  value       = aws_s3_bucket.this.arn
}

output "bucket_domain_name" {
  description = "The bucket domain name (e.g., bucket-name.s3.amazonaws.com)."
  value       = aws_s3_bucket.this.bucket_domain_name
}

output "bucket_regional_domain_name" {
  description = "The bucket region-specific domain name (e.g., bucket-name.s3.us-east-1.amazonaws.com)."
  value       = aws_s3_bucket.this.bucket_regional_domain_name
}

output "bucket_hosted_zone_id" {
  description = "The Route 53 Hosted Zone ID for this bucket's region (for alias records)."
  value       = aws_s3_bucket.this.hosted_zone_id
}

output "bucket_region" {
  description = "The AWS region this bucket resides in."
  value       = aws_s3_bucket.this.region
}

################################################################################
# Bucket Policy
################################################################################

output "bucket_policy" {
  description = "The policy document attached to the bucket (null if no policy)."
  value       = local.create_bucket_policy ? aws_s3_bucket_policy.this[0].policy : null
}

################################################################################
# Versioning
################################################################################

output "versioning_enabled" {
  description = "Whether versioning is enabled on the bucket."
  value       = var.versioning_enabled
}

################################################################################
# Encryption
################################################################################

output "encryption_algorithm" {
  description = "The server-side encryption algorithm used (AES256 or aws:kms)."
  value       = local.use_kms_encryption ? "aws:kms" : "AES256"
}

output "kms_key_id" {
  description = "The KMS key ID used for encryption (null if using SSE-S3)."
  value       = var.kms_key_id
}
