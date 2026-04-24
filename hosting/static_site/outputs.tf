################################################################################
# Hosting Bucket
################################################################################

output "hosting_bucket_id" {
  description = "Name of the S3 hosting bucket."
  value       = module.hosting.bucket_id
}

output "hosting_bucket_arn" {
  description = "ARN of the S3 hosting bucket."
  value       = module.hosting.bucket_arn
}

output "hosting_bucket_regional_domain_name" {
  description = "Regional domain name of the S3 hosting bucket (used as CloudFront origin)."
  value       = module.hosting.bucket_regional_domain_name
}

output "hosting_bucket_region" {
  description = "AWS region where the hosting bucket lives."
  value       = module.hosting.bucket_region
}

################################################################################
# CloudFront Distributions
################################################################################

output "distribution_ids" {
  description = "Map of distribution key -> CloudFront distribution ID."
  value       = module.cdn.distribution_ids
}

output "distribution_arns" {
  description = "Map of distribution key -> CloudFront distribution ARN."
  value       = module.cdn.distribution_arns
}

output "distribution_domain_names" {
  description = "Map of distribution key -> CloudFront distribution domain name (e.g. 'd123.cloudfront.net')."
  value       = module.cdn.distribution_domain_names
}

output "distribution_hosted_zone_ids" {
  description = "Map of distribution key -> CloudFront Route53 zone ID for alias records."
  value       = module.cdn.distribution_hosted_zone_ids
}

################################################################################
# Edge / Versioning
################################################################################

output "cloudfront_function_arn" {
  description = "ARN of the viewer-request rewriter function."
  value       = aws_cloudfront_function.this.arn
}

output "key_value_store_arn" {
  description = "ARN of the CloudFront KeyValueStore that holds host -> version mappings."
  value       = aws_cloudfront_key_value_store.this.arn
}

output "key_value_store_id" {
  description = "ID of the CloudFront KeyValueStore."
  value       = aws_cloudfront_key_value_store.this.id
}

output "default_version" {
  description = "Version prefix the function falls back to when KVS has no host or active entry. The 'active' KVS key is seeded to this on first apply."
  value       = var.default_version
}

################################################################################
# Response Headers Policies
################################################################################

output "html_response_headers_policy_id" {
  description = "ID of the module-managed response headers policy attached to the `*.html` ordered behavior. Null when manage_response_headers_policies = false."
  value       = local.html_response_headers_policy_id
}

output "assets_response_headers_policy_id" {
  description = "ID of the module-managed response headers policy attached to the default cache behavior. Null when manage_response_headers_policies = false. Note: this is the policy the module created; the policy actually attached to the default behavior is var.response_headers_policy_id when set, otherwise this one."
  value       = local.assets_response_headers_policy_id
}

################################################################################
# Deploy Role
################################################################################

output "deploy_role_arn" {
  description = "ARN of the IAM role CI assumes to deploy. Null unless create_deploy_role = true."
  value       = var.create_deploy_role ? aws_iam_role.deploy[0].arn : null
}

output "deploy_role_name" {
  description = "Name of the IAM deploy role. Null unless create_deploy_role = true."
  value       = var.create_deploy_role ? aws_iam_role.deploy[0].name : null
}

################################################################################
# Convenience
################################################################################

output "set_active_version_command" {
  description = "Bash snippet that flips the 'active' KVS key to a new version. Set VERSION before running. Reads the current KVS ETag with describe-key-value-store and passes it via --if-match (KVS requires optimistic concurrency)."
  value       = <<-EOT
    KVS_ARN=${aws_cloudfront_key_value_store.this.arn}
    ETAG=$(aws cloudfront-keyvaluestore describe-key-value-store --kvs-arn $KVS_ARN --query ETag --output text)
    aws cloudfront-keyvaluestore put-key --kvs-arn $KVS_ARN --if-match $ETAG --key active --value $VERSION
  EOT
}

output "invalidation_commands" {
  description = "Map of distribution key -> ready-to-run AWS CLI command that invalidates the entire distribution. Versioned deploys do not need invalidations (each promotion produces a fresh cache key); kept as an escape hatch."
  value = {
    for k, id in module.cdn.distribution_ids :
    k => "aws cloudfront create-invalidation --distribution-id ${id} --paths '/*'"
  }
}
