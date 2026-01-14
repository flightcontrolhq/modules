################################################################################
# Local Values
################################################################################

locals {
  # Tags
  default_tags = {
    ManagedBy = "terraform"
    Module    = "storage/s3"
  }
  tags = merge(local.default_tags, var.tags)

  # Encryption configuration
  use_kms_encryption = var.kms_key_id != null

  # Lifecycle configuration - create only when rules are provided
  create_lifecycle_configuration = length(var.lifecycle_rules) > 0

  # Bucket policy configuration
  # Create bucket policy when either policy templates are specified or custom policy is provided
  create_bucket_policy = length(var.policy_templates) > 0 || var.custom_policy != null
}
