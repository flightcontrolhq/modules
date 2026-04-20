################################################################################
# CloudFront Distributions
#
# Composes cdn/cloudfront. All distributions share the same S3 hosting origin
# and cache behaviors; per-distribution config (aliases, ACM cert, comment)
# comes from var.distributions and is forwarded as-is.
#
# The viewer-request CloudFront Function rewrites every URI to /<version>/...
# before the cache lookup, so each promoted version produces a fresh cache key
# automatically — no CreateInvalidation, no custom_error_responses needed.
################################################################################

module "cdn" {
  source = "../../cdn/cloudfront"

  name = var.name

  distributions = var.distributions

  origins = [
    {
      origin_id      = local.origin_id
      domain_name    = module.hosting.bucket_regional_domain_name
      s3_origin      = true
      custom_headers = var.additional_origin_headers
      origin_shield = var.origin_shield_region == null ? null : {
        enabled              = true
        origin_shield_region = var.origin_shield_region
      }
    }
  ]

  default_cache_behavior = {
    target_origin_id             = local.origin_id
    viewer_protocol_policy       = "redirect-to-https"
    allowed_methods              = ["GET", "HEAD", "OPTIONS"]
    cached_methods               = ["GET", "HEAD"]
    compress                     = true
    cache_policy_id              = var.cache_policy_id
    origin_request_policy_id     = var.origin_request_policy_id
    response_headers_policy_id   = var.response_headers_policy_id
    function_associations        = local.cff_associations
    lambda_function_associations = []
  }

  ordered_cache_behaviors = local.ordered_behaviors

  default_root_object = var.default_root_object
  price_class         = var.price_class
  http_version        = "http2and3"
  is_ipv6_enabled     = true
  wait_for_deployment = var.wait_for_deployment

  minimum_protocol_version = var.minimum_protocol_version

  geo_restriction_type      = var.geo_restriction_type
  geo_restriction_locations = var.geo_restriction_locations

  web_acl_id = var.web_acl_id

  enable_logging                = var.enable_logging
  create_logging_bucket         = var.create_logging_bucket
  logging_bucket_domain_name    = var.logging_bucket_domain_name
  logging_prefix                = var.logging_prefix
  logging_bucket_retention_days = var.logging_retention_days

  tags = local.tags
}
