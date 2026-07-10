################################################################################
# CloudFront Distributions
#
# Composes cdn/cloudfront. All distributions share the same S3 hosting origin
# and cache behaviors; per-distribution config (aliases, ACM cert, comment)
# comes from var.distributions and is forwarded as-is.
#
# In versioned mode the viewer-request function rewrites before cache lookup.
# In SWR mode it keeps the URI stable and passes the active version to the
# origin-facing Lambda@Edge function.
#
# The viewer-response CloudFront Function (created when cache_control_enabled =
# true, the default) sets Cache-Control on every response based on the
# request URI shape. CDN SWR headers are injected separately on origin response.
################################################################################

module "cdn" {
  source = "../../cdn/cloudfront"

  providers = {
    aws = aws.us_east_1
  }

  name = var.name

  distributions = var.distributions

  origins = [
    {
      origin_id         = local.origin_id
      domain_name       = module.hosting.bucket_regional_domain_name
      s3_origin_enabled = true
      custom_headers    = var.additional_origin_headers
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
    compression_enabled          = true
    cache_policy_id              = local.effective_cache_policy_id
    origin_request_policy_id     = local.effective_origin_policy_id
    response_headers_policy_id   = local.effective_response_headers_policy_id
    function_associations        = local.cff_associations
    lambda_function_associations = local.lambda_edge_associations
  }

  ordered_cache_behaviors = local.ordered_behaviors

  default_root_object     = var.default_root_object
  price_class             = var.price_class
  http_version            = "http2and3"
  ipv6_enabled            = true
  deployment_wait_enabled = var.deployment_wait_enabled

  minimum_protocol_version = var.minimum_protocol_version

  geo_restriction_type      = var.geo_restriction_type
  geo_restriction_locations = var.geo_restriction_locations

  web_acl_id = var.web_acl_id

  logging_enabled                 = var.logging_enabled
  logging_bucket_creation_enabled = var.logging_bucket_creation_enabled
  logging_bucket_domain_name      = var.logging_bucket_domain_name
  logging_prefix                  = var.logging_prefix
  logging_bucket_retention_days   = var.logging_retention_days

  tags = local.tags
}
