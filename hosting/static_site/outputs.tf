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
# CloudFront Distributions (passthrough from cdn/cloudfront)
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
# Edge Compute
################################################################################

output "cloudfront_function_arn" {
  description = "ARN of the CloudFront Function (null in spa mode)."
  value       = local.uses_cloudfront_function ? aws_cloudfront_function.this[0].arn : null
}

output "lambda_edge_function_arn" {
  description = "Unqualified ARN of the Lambda@Edge function (null unless mode = 'filesystem_previews')."
  value       = local.uses_lambda_edge ? module.edge_lambda[0].function_arn : null
}

output "lambda_edge_qualified_arn" {
  description = "Versioned (qualified) ARN of the Lambda@Edge function used by CloudFront associations (null unless mode = 'filesystem_previews')."
  value       = local.uses_lambda_edge ? module.edge_lambda[0].function_qualified_arn : null
}

output "lambda_edge_role_arn" {
  description = "IAM role ARN attached to the Lambda@Edge function (null unless mode = 'filesystem_previews')."
  value       = local.uses_lambda_edge ? module.edge_lambda[0].role_arn : null
}

output "key_value_store_arn" {
  description = "ARN of the CloudFront KeyValueStore (null unless mode = 'filesystem_previews' and create_key_value_store = true)."
  value       = local.uses_kvs ? aws_cloudfront_key_value_store.this[0].arn : null
}

output "key_value_store_id" {
  description = "ID of the CloudFront KeyValueStore (null unless mode = 'filesystem_previews' and create_key_value_store = true)."
  value       = local.uses_kvs ? aws_cloudfront_key_value_store.this[0].id : null
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

output "invalidation_commands" {
  description = "Map of distribution key -> ready-to-run AWS CLI command that invalidates the entire distribution. Use after `aws s3 sync` from CI."
  value = {
    for k, id in module.cdn.distribution_ids :
    k => "aws cloudfront create-invalidation --distribution-id ${id} --paths '/*'"
  }
}
