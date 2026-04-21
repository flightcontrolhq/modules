################################################################################
# KMS Key
#
# Supports both symmetric and asymmetric KMS customer master keys. Cryptographic
# shape is set via var.key_spec / var.key_usage; the key policy adapts to the
# shape (e.g. signer_role_arns translates to kms:Sign for SIGN_VERIFY keys and
# to kms:GenerateMac for GENERATE_VERIFY_MAC keys).
#
# CloudTrail captures every KMS API call (including kms:Sign / kms:Decrypt /
# kms:GenerateDataKey) automatically as a CloudTrail management event. No
# per-key configuration is required by this module; the org/account trail must
# exist and be enabled at the composition level.
#
# Rotation:
#   - SYMMETRIC_DEFAULT keys: annual automatic rotation when
#     enable_key_rotation = true.
#   - Asymmetric / HMAC keys: AWS does not support automatic rotation. Use a
#     manual rotation runbook (create-new -> dual-publish -> switch -> retire).
################################################################################

data "aws_caller_identity" "current" {}

# Policy statements are composed as HCL objects and then jsonencode'd at the
# bottom of this file. Building them this way (rather than via
# aws_iam_policy_document) keeps the module testable under mock_provider and
# lets the consumer assert against jsondecode(aws_kms_key.this.policy).
locals {
  root_statement = {
    Sid       = "EnableIAMUserPermissions"
    Effect    = "Allow"
    Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
    Action    = "kms:*"
    Resource  = "*"
  }

  admin_statement = length(var.key_administrator_role_arns) > 0 ? [{
    Sid       = "AllowKeyAdministration"
    Effect    = "Allow"
    Principal = { AWS = var.key_administrator_role_arns }
    Action = [
      "kms:Describe*",
      "kms:Get*",
      "kms:List*",
      "kms:Put*",
      "kms:Update*",
      "kms:Enable*",
      "kms:Disable*",
      "kms:TagResource",
      "kms:UntagResource",
      "kms:ScheduleKeyDeletion",
      "kms:CancelKeyDeletion",
      "kms:Create*",
      "kms:Delete*",
      "kms:Revoke*",
    ]
    Resource = "*"
  }] : []

  # Cryptographic-use actions, derived from key_usage.
  key_user_actions = {
    ENCRYPT_DECRYPT = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncryptFrom",
      "kms:ReEncryptTo",
      "kms:GenerateDataKey",
      "kms:GenerateDataKeyWithoutPlaintext",
      "kms:GenerateDataKeyPair",
      "kms:GenerateDataKeyPairWithoutPlaintext",
      "kms:DescribeKey",
    ]
    SIGN_VERIFY = [
      "kms:Verify",
      "kms:GetPublicKey",
      "kms:DescribeKey",
    ]
    GENERATE_VERIFY_MAC = [
      "kms:VerifyMac",
      "kms:DescribeKey",
    ]
    KEY_AGREEMENT = [
      "kms:DeriveSharedSecret",
      "kms:GetPublicKey",
      "kms:DescribeKey",
    ]
  }

  # Signer/MAC-generator actions, derived from key_usage. Non-signing usages
  # render an empty list so the AllowSign statement is omitted regardless of
  # whether the caller supplied signer_role_arns.
  signer_actions = {
    ENCRYPT_DECRYPT = []
    SIGN_VERIFY = [
      "kms:Sign",
      "kms:GetPublicKey",
      "kms:DescribeKey",
    ]
    GENERATE_VERIFY_MAC = [
      "kms:GenerateMac",
      "kms:DescribeKey",
    ]
    KEY_AGREEMENT = []
  }

  user_statement = length(var.key_user_role_arns) > 0 ? [{
    Sid       = "AllowKeyUse"
    Effect    = "Allow"
    Principal = { AWS = var.key_user_role_arns }
    Action    = local.key_user_actions[var.key_usage]
    Resource  = "*"
  }] : []

  signer_statement = (
    length(var.signer_role_arns) > 0 && length(local.signer_actions[var.key_usage]) > 0
    ? [{
      Sid       = "AllowSign"
      Effect    = "Allow"
      Principal = { AWS = var.signer_role_arns }
      Action    = local.signer_actions[var.key_usage]
      Resource  = "*"
    }]
    : []
  )

  public_key_reader_statement = length(var.public_key_reader_role_arns) > 0 ? [{
    Sid       = "AllowPublicKeyRead"
    Effect    = "Allow"
    Principal = { AWS = var.public_key_reader_role_arns }
    Action = [
      "kms:GetPublicKey",
      "kms:DescribeKey",
    ]
    Resource = "*"
  }] : []

  key_policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [local.root_statement],
      local.admin_statement,
      local.user_statement,
      local.signer_statement,
      local.public_key_reader_statement,
    )
  })
}

resource "aws_kms_key" "this" {
  description              = local.description
  customer_master_key_spec = var.key_spec
  key_usage                = var.key_usage
  multi_region             = var.multi_region
  enable_key_rotation      = local.enable_key_rotation
  deletion_window_in_days  = var.deletion_window_in_days

  policy = local.key_policy

  tags = local.tags
}

resource "aws_kms_alias" "this" {
  name          = local.alias_name
  target_key_id = aws_kms_key.this.key_id
}
