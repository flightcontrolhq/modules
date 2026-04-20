################################################################################
# CloudFront Function
#
# Single viewer-request rewriter that handles both routing styles. Reads the
# active version from the KVS on every invocation and rewrites the URI to
# /<version>/... before the cache lookup.
################################################################################

locals {
  cff_code = templatefile("${path.module}/functions/rewrite.js", {
    kvs_id          = aws_cloudfront_key_value_store.this.id
    default_version = var.default_version
    index_document  = var.default_root_object
    routing         = var.routing
  })
}

resource "aws_cloudfront_function" "this" {
  name    = local.cff_name
  runtime = "cloudfront-js-2.0"
  comment = "${var.name} ${var.routing} viewer-request rewriter"
  publish = true
  code    = local.cff_code

  key_value_store_associations = [aws_cloudfront_key_value_store.this.arn]
}
