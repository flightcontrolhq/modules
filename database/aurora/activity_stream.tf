################################################################################
# Database Activity Stream
################################################################################

resource "aws_rds_cluster_activity_stream" "this" {
  count = var.enable_activity_stream ? 1 : 0

  resource_arn = aws_rds_cluster.this.arn
  mode         = var.activity_stream_mode
  kms_key_id   = var.activity_stream_kms_key_id

  engine_native_audit_fields_included = true

  depends_on = [
    aws_rds_cluster_instance.this,
  ]
}
