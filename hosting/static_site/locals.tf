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

  cff_associations = [{
    event_type   = "viewer-request"
    function_arn = aws_cloudfront_function.this.arn
  }]

  managed_cache_disabled_id = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"

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
      response_headers_policy_id   = var.response_headers_policy_id
      function_associations        = local.cff_associations
      lambda_function_associations = []
      realtime_log_config_arn      = null
    }
  ]

  long_cache_behaviors = [
    for path in var.long_cache_paths : {
      path_pattern                 = path
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
      realtime_log_config_arn      = null
    }
  ]

  # Module-managed response headers policy IDs. The default behavior prefers a
  # caller-supplied response_headers_policy_id when set; the HTML behavior
  # always uses the module-managed policy (callers turn it off entirely with
  # manage_response_headers_policies = false).
  assets_response_headers_policy_id = try(aws_cloudfront_response_headers_policy.assets[0].id, null)
  html_response_headers_policy_id   = try(aws_cloudfront_response_headers_policy.html[0].id, null)
  effective_default_response_headers_policy_id = (
    var.response_headers_policy_id != null
    ? var.response_headers_policy_id
    : local.assets_response_headers_policy_id
  )

  html_cache_behaviors = var.manage_response_headers_policies ? [{
    path_pattern                 = var.html_path_pattern
    target_origin_id             = local.origin_id
    viewer_protocol_policy       = "redirect-to-https"
    allowed_methods              = ["GET", "HEAD", "OPTIONS"]
    cached_methods               = ["GET", "HEAD"]
    compress                     = true
    cache_policy_id              = var.cache_policy_id
    origin_request_policy_id     = var.origin_request_policy_id
    response_headers_policy_id   = local.html_response_headers_policy_id
    function_associations        = local.cff_associations
    lambda_function_associations = []
    realtime_log_config_arn      = null
  }] : []

  # CloudFront evaluates ordered behaviors top-down. Caller-supplied
  # no_cache_paths / long_cache_paths stay first so they win against the
  # generic `*.html` terminal pattern.
  ordered_behaviors = concat(
    local.no_cache_behaviors,
    local.long_cache_behaviors,
    local.html_cache_behaviors,
  )

  cff_name           = substr(replace("${var.name}-rewrite", "/[^a-zA-Z0-9-_]/", "-"), 0, 64)
  kvs_name           = substr(replace("${var.name}-kvs", "/[^a-zA-Z0-9-]/", "-"), 0, 64)
  deploy_role_name   = var.deploy_role_name != null ? var.deploy_role_name : "${var.name}-deploy"
  oac_policy_sid     = "AllowCloudFrontServicePrincipal"
  partition          = data.aws_partition.current.partition
  account_id         = data.aws_caller_identity.current.account_id
  hosting_bucket_arn = "arn:${local.partition}:s3:::${var.name}"
}
