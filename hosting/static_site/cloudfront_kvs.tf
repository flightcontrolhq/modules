################################################################################
# CloudFront KeyValueStore
#
# Holds the host -> version map read by the rewriter function on every viewer
# request. Always created — versioning is the only deploy model.
#
# Seed entries:
#   - 'active' is always seeded with var.default_version so a fresh stack works
#     before the first KVS edit. Override by including 'active' in
#     var.kvs_initial_data.
#   - Additional entries from kvs_initial_data are managed individually (not
#     `aws_cloudfrontkeyvaluestore_keys_exclusive`) so previews added/removed
#     out-of-band by CI are not stomped by Terraform.
################################################################################

resource "aws_cloudfront_key_value_store" "this" {
  name    = local.kvs_name
  comment = "${var.name} host -> version lookup"
}

resource "aws_cloudfrontkeyvaluestore_key" "seed" {
  for_each = local.active_kvs_seed

  key_value_store_arn = aws_cloudfront_key_value_store.this.arn
  key                 = each.key
  value               = each.value
}
