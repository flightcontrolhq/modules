################################################################################
# Model Invocation Logging
################################################################################

resource "aws_bedrock_model_invocation_logging_configuration" "this" {
  count = var.model_invocation_logging_enabled ? 1 : 0

  region = var.region

  logging_config {
    text_data_delivery_enabled      = var.text_data_delivery_enabled
    image_data_delivery_enabled     = var.image_data_delivery_enabled
    embedding_data_delivery_enabled = var.embedding_data_delivery_enabled
    video_data_delivery_enabled     = var.video_data_delivery_enabled

    cloudwatch_config {
      log_group_name = aws_cloudwatch_log_group.model_invocations[0].name
      role_arn       = aws_iam_role.model_invocation_logging[0].arn
    }
  }

  lifecycle {
    precondition {
      condition = anytrue([
        var.text_data_delivery_enabled,
        var.image_data_delivery_enabled,
        var.embedding_data_delivery_enabled,
        var.video_data_delivery_enabled,
      ])
      error_message = "At least one invocation data delivery type must be enabled."
    }
  }

  depends_on = [aws_iam_role_policy.model_invocation_logging]
}
