################################################################################
# CloudWatch Log Group
################################################################################

resource "aws_cloudwatch_log_group" "this" {
  count = var.create_log_group ? 1 : 0

  name              = local.log_group_name
  retention_in_days = var.log_retention_days == 0 ? null : var.log_retention_days
  kms_key_id        = var.log_kms_key_id
  tags              = local.tags
}
