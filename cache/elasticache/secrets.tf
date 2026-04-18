################################################################################
# Secrets Manager - Connection String
################################################################################

module "connection_string_secret" {
  count = local.create_secret ? 1 : 0

  source = "../../security/secrets_manager"

  name        = local.secret_name
  description = "Connection string for ElastiCache ${var.engine} '${var.name}'"

  secret_string = local.connection_string

  kms_key_id              = var.secret_kms_key_arn
  recovery_window_in_days = var.secret_recovery_window_in_days

  tags = local.tags
}
