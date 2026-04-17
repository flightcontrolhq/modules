################################################################################
# CloudFront KeyValueStore
#
# Used by the filesystem_previews CloudFront Function to map request Host
# headers (typically PR/branch preview subdomains) to S3 deployment prefixes
# without an extra round trip. Created only when create_key_value_store = true
# and mode = 'filesystem_previews'.
#
# Initial entries supplied via kvs_initial_data are managed as individual
# `aws_cloudfrontkeyvaluestore_key` resources. This is intentional, not
# `aws_cloudfrontkeyvaluestore_keys_exclusive`: exclusive mode would delete
# preview entries created out-of-band by CI when adding/removing PR previews.
# The seed map is meant for long-lived hosts (e.g., the production canonical
# alias if you want to override the default prefix); ephemeral previews should
# be added/removed by CI via `aws cloudfront-keyvaluestore put-key` /
# `delete-key`.
################################################################################

resource "aws_cloudfront_key_value_store" "this" {
  count = local.uses_kvs ? 1 : 0

  name    = local.kvs_name
  comment = "${var.name} preview host -> deployment prefix lookup"
}

resource "aws_cloudfrontkeyvaluestore_key" "seed" {
  for_each = local.uses_kvs ? var.kvs_initial_data : {}

  key_value_store_arn = aws_cloudfront_key_value_store.this[0].arn
  key                 = each.key
  value               = each.value
}
