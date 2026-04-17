locals {
  default_tags = {
    ManagedBy = "terraform"
    Module    = "hosting/static_site"
  }
  tags = merge(local.default_tags, var.tags)

  is_spa                 = var.mode == "spa"
  is_filesystem          = var.mode == "filesystem"
  is_filesystem_previews = var.mode == "filesystem_previews"

  uses_cloudfront_function = local.is_filesystem || local.is_filesystem_previews
  uses_lambda_edge         = local.is_filesystem_previews
  uses_kvs                 = local.is_filesystem_previews && var.create_key_value_store

  origin_id = "s3-hosting"

  edge_origin_headers = local.is_filesystem_previews ? concat([
    {
      name  = "static_mode"
      value = var.static_mode_header_value
    },
    {
      name  = "x-fc-deployment-id"
      value = var.deployment_id_header_value
    },
    {
      name  = "x-fc-region"
      value = data.aws_region.current.region
    },
    {
      name  = "x-fc-trailing-slash"
      value = var.trailing_slash_enabled ? "Enabled" : "Disabled"
    },
    ], var.preview_url_header_value != "" ? [{
      name  = "x-fc-preview-url"
      value = var.preview_url_header_value
  }] : []) : []

  origin_custom_headers = concat(local.edge_origin_headers, var.additional_origin_headers)

  cff_associations = local.uses_cloudfront_function ? [{
    event_type   = "viewer-request"
    function_arn = aws_cloudfront_function.this[0].arn
  }] : []

  edge_associations = local.uses_lambda_edge ? [{
    event_type   = "origin-request"
    lambda_arn   = module.edge_lambda[0].function_qualified_arn
    include_body = false
  }] : []

  managed_cache_disabled_id = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"

  no_cache_behaviors = [
    for path in var.no_cache_paths : {
      path_pattern               = path
      target_origin_id           = local.origin_id
      viewer_protocol_policy     = "redirect-to-https"
      allowed_methods            = ["GET", "HEAD", "OPTIONS"]
      cached_methods             = ["GET", "HEAD"]
      compress                   = true
      cache_policy_id            = local.managed_cache_disabled_id
      origin_request_policy_id   = var.origin_request_policy_id
      response_headers_policy_id = var.response_headers_policy_id
      function_associations      = local.cff_associations
      lambda_function_associations = [
        for a in local.edge_associations : a
      ]
      realtime_log_config_arn = null
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
      lambda_function_associations = local.edge_associations
      realtime_log_config_arn      = null
    }
  ]

  ordered_behaviors = concat(local.no_cache_behaviors, local.long_cache_behaviors)

  spa_error_responses = local.is_spa ? [
    {
      error_code            = 403
      response_code         = 200
      response_page_path    = "/${var.default_root_object}"
      error_caching_min_ttl = var.spa_error_caching_min_ttl
    },
    {
      error_code            = 404
      response_code         = 200
      response_page_path    = "/${var.default_root_object}"
      error_caching_min_ttl = var.spa_error_caching_min_ttl
    }
  ] : []

  lambda_source_dir  = var.lambda_source_dir != null ? var.lambda_source_dir : "${path.module}/edge/handler"
  lambda_zip_path    = "${path.module}/.terraform/tmp/${var.name}-edge.zip"
  lambda_name        = substr("${var.name}-edge", 0, 64)
  cff_name           = substr(replace("${var.name}-rewrite", "/[^a-zA-Z0-9-_]/", "-"), 0, 64)
  kvs_name           = substr(replace("${var.name}-kvs", "/[^a-zA-Z0-9-]/", "-"), 0, 64)
  deploy_role_name   = var.deploy_role_name != null ? var.deploy_role_name : "${var.name}-deploy"
  oac_policy_sid     = "AllowCloudFrontServicePrincipal"
  edge_policy_sid    = "AllowLambdaEdgeRead"
  partition          = data.aws_partition.current.partition
  account_id         = data.aws_caller_identity.current.account_id
  hosting_bucket_arn = "arn:${local.partition}:s3:::${var.name}"
  source_arn_pattern = [for k, _ in var.distributions : "arn:${local.partition}:cloudfront::${local.account_id}:distribution/*"]
}
