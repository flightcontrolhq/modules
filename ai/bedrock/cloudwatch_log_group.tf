################################################################################
# Model Invocation Log Group
################################################################################

resource "aws_cloudwatch_log_group" "model_invocations" {
  count = var.model_invocation_logging_enabled ? 1 : 0

  name              = local.log_group_name
  retention_in_days = var.log_group_retention_days == 0 ? null : var.log_group_retention_days
  kms_key_id        = var.log_group_kms_key_arn

  tags = merge(local.tags, {
    Name = "${var.name}-bedrock-model-invocations"
  })
}
