locals {
  region = coalesce(var.region, data.aws_region.current.id)
}

locals {
  default_tags = {
    ManagedBy = "terraform"
    Module    = "hosting/static_site"
  }
  tags = merge(local.default_tags, var.tags)

  origin_id = "s3-hosting"

  # The CF Function reads `active` from KVS unless callers seed it themselves.
  active_kvs_seed = merge(
    { active = var.default_version },
    var.kvs_initial_data,
  )

  # viewer-request runs first (URI rewrite to /<version>/...), viewer-response
  # runs last (Cache-Control header from rewritten URI shape). Both are
  # attached to every behavior — no_cache_paths included — so the
  # Cache-Control values stay consistent regardless of which behavior matched.
  cff_associations = concat(
    [{
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.rewrite.arn
    }],
    var.manage_cache_control ? [{
      event_type   = "viewer-response"
      function_arn = aws_cloudfront_function.cache_control[0].arn
    }] : [],
  )

  managed_cache_disabled_id = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"

  # Caller-supplied response_headers_policy_id wins over the module-managed
  # one. Both can be null (no policy attached); the cache-control function
  # still runs because it's a separate viewer-response association.
  module_response_headers_policy_id = try(aws_cloudfront_response_headers_policy.this[0].id, null)
  effective_response_headers_policy_id = (
    var.response_headers_policy_id != null
    ? var.response_headers_policy_id
    : local.module_response_headers_policy_id
  )

  no_cache_behaviors = [
    for path in var.no_cache_paths : {
      path_pattern                 = path
      target_origin_id             = local.origin_id
      viewer_protocol_policy       = "redirect-to-https"
      allowed_methods              = ["GET", "HEAD", "OPTIONS"]
      cached_methods               = ["GET", "HEAD"]
      compress                     = true
      cache_policy_id              = local.managed_cache_disabled_id
      origin_request_policy_id     = var.origin_request_policy_id
      response_headers_policy_id   = local.effective_response_headers_policy_id
      function_associations        = local.cff_associations
      lambda_function_associations = []
      realtime_log_config_arn      = null
    }
  ]

  ordered_behaviors = local.no_cache_behaviors

  cff_rewrite_name             = substr(replace("${var.name}-rewrite", "/[^a-zA-Z0-9-_]/", "-"), 0, 64)
  cff_cache_control_name       = substr(replace("${var.name}-cache-ctl", "/[^a-zA-Z0-9-_]/", "-"), 0, 64)
  response_headers_policy_name = substr(replace("${var.name}-rh", "/[^a-zA-Z0-9-_]/", "-"), 0, 64)
  kvs_name                     = substr(replace("${var.name}-kvs", "/[^a-zA-Z0-9-]/", "-"), 0, 64)
  deploy_role_name             = var.deploy_role_name != null ? var.deploy_role_name : "${var.name}-deploy"
  oac_policy_sid               = "AllowCloudFrontServicePrincipal"
  partition                    = data.aws_partition.current.partition
  account_id                   = data.aws_caller_identity.current.account_id
  hosting_bucket_arn           = "arn:${local.partition}:s3:::${var.name}"
}
