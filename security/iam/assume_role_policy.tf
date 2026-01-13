################################################################################
# Assume Role Policy
################################################################################

data "aws_iam_policy_document" "assume_role" {
  count = local.use_custom_policy ? 0 : 1

  # Trust AWS service principals
  dynamic "statement" {
    for_each = local.has_trusted_services ? [1] : []
    content {
      sid     = "TrustServices"
      effect  = "Allow"
      actions = ["sts:AssumeRole"]

      principals {
        type        = "Service"
        identifiers = var.trusted_services
      }

      dynamic "condition" {
        for_each = var.assume_role_conditions
        content {
          test     = condition.value.test
          variable = condition.value.variable
          values   = condition.value.values
        }
      }
    }
  }

  # Trust AWS account IDs and IAM ARNs
  dynamic "statement" {
    for_each = local.has_aws_principals ? [1] : []
    content {
      sid     = "TrustAWSPrincipals"
      effect  = "Allow"
      actions = ["sts:AssumeRole"]

      principals {
        type        = "AWS"
        identifiers = var.trusted_aws_principals
      }

      dynamic "condition" {
        for_each = var.assume_role_conditions
        content {
          test     = condition.value.test
          variable = condition.value.variable
          values   = condition.value.values
        }
      }
    }
  }

  # Trust OIDC identity providers
  dynamic "statement" {
    for_each = var.trusted_oidc_providers
    content {
      sid     = "TrustOIDCProvider${statement.key}"
      effect  = "Allow"
      actions = ["sts:AssumeRoleWithWebIdentity"]

      principals {
        type        = "Federated"
        identifiers = [statement.value.provider_arn]
      }

      dynamic "condition" {
        for_each = statement.value.conditions
        content {
          test     = condition.value.test
          variable = condition.value.variable
          values   = condition.value.values
        }
      }

      # Apply global assume role conditions
      dynamic "condition" {
        for_each = var.assume_role_conditions
        content {
          test     = condition.value.test
          variable = condition.value.variable
          values   = condition.value.values
        }
      }
    }
  }

  # Trust SAML identity providers
  dynamic "statement" {
    for_each = local.has_saml_providers ? [1] : []
    content {
      sid     = "TrustSAMLProviders"
      effect  = "Allow"
      actions = ["sts:AssumeRoleWithSAML"]

      principals {
        type        = "Federated"
        identifiers = var.trusted_saml_providers
      }

      condition {
        test     = "StringEquals"
        variable = "SAML:aud"
        values   = ["https://signin.aws.amazon.com/saml"]
      }

      dynamic "condition" {
        for_each = var.assume_role_conditions
        content {
          test     = condition.value.test
          variable = condition.value.variable
          values   = condition.value.values
        }
      }
    }
  }
}

################################################################################
# Computed Assume Role Policy
################################################################################

locals {
  assume_role_policy = local.use_custom_policy ? var.custom_assume_role_policy : data.aws_iam_policy_document.assume_role[0].json
}
