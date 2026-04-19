################################################################################
# Secrets Manager Secret
################################################################################

resource "aws_secretsmanager_secret" "this" {
  name                    = var.name
  description             = var.description
  kms_key_id              = var.kms_key_id
  recovery_window_in_days = var.recovery_window_in_days

  tags = merge(local.tags, {
    Name = var.name
  })

  lifecycle {
    precondition {
      condition     = !(var.secret_string != null && var.secret_json != null)
      error_message = "Only one of secret_string or secret_json may be provided."
    }
  }
}

resource "aws_secretsmanager_secret_version" "this" {
  count = var.create_version ? 1 : 0

  secret_id     = aws_secretsmanager_secret.this.id
  secret_string = local.secret_value
}

resource "aws_secretsmanager_secret_policy" "this" {
  count = var.policy == null ? 0 : 1

  secret_arn = aws_secretsmanager_secret.this.arn
  policy     = var.policy
}
