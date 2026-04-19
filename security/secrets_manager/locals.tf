################################################################################
# Local Values
################################################################################

locals {
  default_tags = {
    ManagedBy = "terraform"
    Module    = "security/secrets_manager"
  }

  tags = merge(local.default_tags, var.tags)

  secret_value = var.secret_json != null ? jsonencode(var.secret_json) : var.secret_string

  # Stable integer trigger for the write-only secret value. A new version is
  # written whenever the plaintext changes; the provider never reads the value
  # back from Secrets Manager. First 8 hex chars of sha256 fit in a 32-bit int.
  secret_value_version = local.secret_value == null ? null : parseint(substr(sha256(local.secret_value), 0, 8), 16)
}
