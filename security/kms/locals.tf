################################################################################
# Local Values
################################################################################

locals {
  alias_name = "alias/${coalesce(var.alias, var.name)}"

  description = coalesce(var.description, "KMS key for ${var.name}.")

  is_symmetric_default = var.key_spec == "SYMMETRIC_DEFAULT"

  # Automatic key rotation is only supported for symmetric SYMMETRIC_DEFAULT
  # keys. For all other shapes the attribute must be left null so Terraform
  # does not try to apply a setting AWS will reject.
  enable_key_rotation = local.is_symmetric_default ? var.enable_key_rotation : null

  default_tags = {
    ManagedBy = "terraform"
    Module    = "security/kms"
  }

  tags = merge(local.default_tags, var.tags)
}
