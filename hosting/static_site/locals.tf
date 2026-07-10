locals {
  region = coalesce(var.region, data.aws_region.current.region)
}

locals {
  default_tags = {
    ManagedBy = "terraform"
    Module    = "hosting/static_site"
  }
  tags = merge(local.default_tags, var.tags)

  origin_id = "s3-hosting"

  swr_enabled                  = var.deployment_cache_mode == "stale_while_revalidate"
  effective_html_cache_control = coalesce(var.html_cache_control, local.swr_enabled ? "max-age=0, stale-while-revalidate=300" : "no-cache")
  versioned_cache_policy_id    = coalesce(var.cache_policy_id, "658327ea-f89d-4fab-a63d-7e88639e58f6")
  versioned_origin_policy_id   = coalesce(var.origin_request_policy_id, "88a5eaf4-2fd4-4709-b370-b4c650ea3fcf")
  effective_cache_policy_id    = local.swr_enabled ? aws_cloudfront_cache_policy.swr[0].id : local.versioned_cache_policy_id
  effective_origin_policy_id   = local.swr_enabled ? aws_cloudfront_origin_request_policy.swr[0].id : local.versioned_origin_policy_id

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
    var.cache_control_enabled ? [{
      event_type   = "viewer-response"
      function_arn = aws_cloudfront_function.cache_control[0].arn
    }] : [],
  )

  lambda_edge_associations = local.swr_enabled ? [
    {
      event_type = "origin-request"
      lambda_arn = aws_lambda_function.edge_router[0].qualified_arn
    },
    {
      event_type = "origin-response"
      lambda_arn = aws_lambda_function.edge_router[0].qualified_arn
    },
  ] : []

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
      compression_enabled          = true
      cache_policy_id              = local.managed_cache_disabled_id
      origin_request_policy_id     = local.effective_origin_policy_id
      response_headers_policy_id   = local.effective_response_headers_policy_id
      function_associations        = local.cff_associations
      lambda_function_associations = local.lambda_edge_associations
      realtime_log_config_arn      = null
    }
  ]

  ordered_behaviors = local.no_cache_behaviors

  cff_rewrite_name             = substr(replace("${var.name}-rewrite", "/[^a-zA-Z0-9-_]/", "-"), 0, 64)
  cff_cache_control_name       = substr(replace("${var.name}-cache-ctl", "/[^a-zA-Z0-9-_]/", "-"), 0, 64)
  response_headers_policy_name = substr(replace("${var.name}-rh", "/[^a-zA-Z0-9-_]/", "-"), 0, 64)
  swr_cache_policy_name        = substr(replace("${var.name}-swr-cache", "/[^a-zA-Z0-9-_]/", "-"), 0, 128)
  swr_origin_policy_name       = substr(replace("${var.name}-swr-origin", "/[^a-zA-Z0-9-_]/", "-"), 0, 128)
  edge_router_name             = substr(replace("${var.name}-edge-router", "/[^a-zA-Z0-9-_]/", "-"), 0, 64)
  kvs_name                     = substr(replace("${var.name}-kvs", "/[^a-zA-Z0-9-]/", "-"), 0, 64)
  deploy_role_name             = var.deploy_role_name != null ? var.deploy_role_name : "${var.name}-deploy"
  oac_policy_sid               = "AllowCloudFrontServicePrincipal"
  partition                    = data.aws_partition.current.partition
  hosting_bucket_arn           = "arn:${local.partition}:s3:::${var.name}"
}
