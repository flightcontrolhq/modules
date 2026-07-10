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

  managed_cache_disabled_id = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"

  # AWS-managed SecurityHeadersPolicy: HSTS, X-Content-Type-Options nosniff,
  # X-Frame-Options SAMEORIGIN, Referrer-Policy strict-origin-when-cross-origin,
  # X-XSS-Protection 1; mode=block.
  managed_security_headers_id = "67f7725c-6f97-4210-82d7-5512b31e9d03"

  # Precedence: caller-supplied response_headers_policy_id > module-managed
  # policy from var.response_headers_policy > AWS-managed SecurityHeadersPolicy
  # (attached by default; disable with security_headers_enabled = false). The
  # cache-control function always runs regardless — it's a separate
  # viewer-response association.
  module_response_headers_policy_id = try(aws_cloudfront_response_headers_policy.this[0].id, null)
  effective_response_headers_policy_id = try(coalesce(
    var.response_headers_policy_id,
    local.module_response_headers_policy_id,
    var.security_headers_enabled ? local.managed_security_headers_id : null,
  ), null)

  # Missing objects return real 404s (the bucket policy grants CloudFront
  # s3:ListBucket, so S3 distinguishes NoSuchKey from AccessDenied). When
  # error_document is set, serve it as the 404 body while keeping the 404
  # status. The error-page fetch bypasses the viewer-request rewrite, so the
  # key resolves at the bucket root — deploys copy <version>/404.html there
  # at promotion time. A genuine 403 now only means "blocked" (e.g. WAF),
  # never "file missing", so it is deliberately not mapped.
  custom_error_responses = var.error_document == "" ? [] : [
    {
      error_code            = 404
      response_code         = 404
      response_page_path    = "/${var.error_document}"
      error_caching_min_ttl = var.error_caching_min_ttl
    }
  ]

  no_cache_behaviors = [
    for path in var.no_cache_paths : {
      path_pattern                 = path
      target_origin_id             = local.origin_id
      viewer_protocol_policy       = "redirect-to-https"
      allowed_methods              = ["GET", "HEAD", "OPTIONS"]
      cached_methods               = ["GET", "HEAD"]
      compression_enabled          = true
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
  hosting_bucket_arn           = "arn:${local.partition}:s3:::${var.name}"
}
