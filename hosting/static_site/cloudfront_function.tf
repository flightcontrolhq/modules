################################################################################
# CloudFront Functions
#
# Two viewer-side functions, both attached to every cache behavior:
#
# - rewrite        (viewer-request)  : reads the active version from the KVS
#                                       and rewrites the URI to /<version>/...
#                                       so each promotion produces a fresh
#                                       cache key without invalidations.
# - cache_control  (viewer-response) : sets Cache-Control on every response
#                                       based on the rewritten URI shape.
#                                       HTML responses get a short s-maxage +
#                                       long stale-while-revalidate; asset
#                                       responses get the immutable 1-year
#                                       browser cache. Discrimination at the
#                                       URI level (post-rewrite) avoids the
#                                       cache-behavior-matching pitfall that
#                                       caused ENG-4785.
################################################################################

locals {
  cff_rewrite_code = templatefile("${path.module}/functions/rewrite.js", {
    kvs_id          = aws_cloudfront_key_value_store.this.id
    default_version = var.default_version
    index_document  = var.default_root_object
    routing         = var.routing
  })

  cff_cache_control_code = templatefile("${path.module}/functions/cache_control.js", {
    html_cache_control  = var.html_cache_control
    asset_cache_control = var.assets_cache_control
    html_overrides_json = jsonencode(var.html_path_overrides)
  })
}

resource "aws_cloudfront_function" "rewrite" {
  provider = aws.us_east_1

  name    = local.cff_rewrite_name
  runtime = "cloudfront-js-2.0"
  comment = "${var.name} ${var.routing} viewer-request rewriter"
  publish = true
  code    = local.cff_rewrite_code

  key_value_store_associations = [aws_cloudfront_key_value_store.this.arn]
}

resource "aws_cloudfront_function" "cache_control" {
  count = var.manage_cache_control ? 1 : 0

  provider = aws.us_east_1

  name    = local.cff_cache_control_name
  runtime = "cloudfront-js-2.0"
  comment = "${var.name} viewer-response Cache-Control writer"
  publish = true
  code    = local.cff_cache_control_code
}
