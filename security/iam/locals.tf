################################################################################
# Local Values
################################################################################

locals {
  # Default tags applied to all resources
  default_tags = {
    ManagedBy = "terraform"
    Module    = "security/iam"
  }

  # Merge default tags with user-provided tags
  tags = merge(local.default_tags, var.tags)

  # Feature detection flags
  has_trusted_services         = length(var.trusted_services) > 0
  has_aws_principals           = length(var.trusted_aws_principals) > 0
  has_oidc_providers           = length(var.trusted_oidc_providers) > 0
  has_saml_providers           = length(var.trusted_saml_providers) > 0
  use_custom_policy            = var.custom_assume_role_policy != null
  has_inline_policy_statements = length(var.inline_policy_statements) > 0
}
