################################################################################
# CloudFront Function
#
# Created in 'filesystem' and 'filesystem_previews' modes only. Runs at every
# edge POP on viewer-request, before the cache lookup. Used for cheap path
# rewriting (filesystem mode) and KVS-backed deployment prefix resolution
# (filesystem_previews mode).
################################################################################

locals {
  cff_template_path = local.is_filesystem ? "${path.module}/functions/filesystem.js" : "${path.module}/functions/filesystem_previews.js"

  cff_vars = local.is_filesystem ? {
    index_document = var.default_root_object
    } : {
    kvs_id         = local.uses_kvs ? aws_cloudfront_key_value_store.this[0].id : ""
    default_prefix = var.deployment_id_header_value
  }

  cff_code = local.uses_cloudfront_function ? templatefile(local.cff_template_path, local.cff_vars) : ""
}

resource "aws_cloudfront_function" "this" {
  count = local.uses_cloudfront_function ? 1 : 0

  name    = local.cff_name
  runtime = "cloudfront-js-2.0"
  comment = "${var.name} ${var.mode} viewer-request rewriter"
  publish = true
  code    = local.cff_code

  key_value_store_associations = local.uses_kvs ? [aws_cloudfront_key_value_store.this[0].arn] : []
}
