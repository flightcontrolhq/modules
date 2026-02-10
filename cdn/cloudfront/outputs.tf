################################################################################
# Distribution
################################################################################

output "distribution_ids" {
  description = "A map of distribution key to CloudFront distribution ID."
  value       = { for k, v in aws_cloudfront_distribution.this : k => v.id }
}

output "distribution_arns" {
  description = "A map of distribution key to CloudFront distribution ARN."
  value       = { for k, v in aws_cloudfront_distribution.this : k => v.arn }
}

output "distribution_domain_names" {
  description = "A map of distribution key to CloudFront distribution domain name."
  value       = { for k, v in aws_cloudfront_distribution.this : k => v.domain_name }
}

output "distribution_hosted_zone_ids" {
  description = "A map of distribution key to CloudFront Route 53 zone ID for alias records."
  value       = { for k, v in aws_cloudfront_distribution.this : k => v.hosted_zone_id }
}

output "distribution_statuses" {
  description = "A map of distribution key to current status of the distribution."
  value       = { for k, v in aws_cloudfront_distribution.this : k => v.status }
}

output "distribution_etags" {
  description = "A map of distribution key to current version of the distribution's information."
  value       = { for k, v in aws_cloudfront_distribution.this : k => v.etag }
}

################################################################################
# Origin Access Control
################################################################################

output "origin_access_control_ids" {
  description = "A map of origin_id to OAC ID for S3 origins."
  value       = { for k, v in aws_cloudfront_origin_access_control.this : k => v.id }
}

################################################################################
# Logging
################################################################################

output "logging_bucket_id" {
  description = "The ID of the logging S3 bucket."
  value       = var.create_logging_bucket ? aws_s3_bucket.logging[0].id : null
}

output "logging_bucket_arn" {
  description = "The ARN of the logging S3 bucket."
  value       = var.create_logging_bucket ? aws_s3_bucket.logging[0].arn : null
}

output "logging_bucket_domain_name" {
  description = "The domain name of the logging S3 bucket."
  value       = var.create_logging_bucket ? aws_s3_bucket.logging[0].bucket_domain_name : null
}
