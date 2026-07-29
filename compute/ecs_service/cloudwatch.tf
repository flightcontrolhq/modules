################################################################################
# CloudWatch Log Group
################################################################################

# Explicitly manage the log group used by the awslogs driver so it always
# exists before a task starts. Relying solely on awslogs-create-group is
# unreliable (especially on Fargate) and only applies to task definitions that
# carry that option, not necessarily the one deployed by the external
# deployment controller.
resource "aws_cloudwatch_log_group" "this" {
  name              = "/ecs/${var.name}"
  retention_in_days = var.log_retention_days == 0 ? null : var.log_retention_days
  kms_key_id        = var.log_kms_key_id

  tags = merge(local.tags, {
    Name = "/ecs/${var.name}"
  })
}
