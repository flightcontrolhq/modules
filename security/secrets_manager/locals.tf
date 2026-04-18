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
}
