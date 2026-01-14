################################################################################
# S3 Bucket Full Configuration Fixture
#
# Creates an S3 bucket with ALL features enabled for comprehensive Terratest
# integration testing. This fixture validates all module features together:
# - SSE-KMS encryption with bucket key
# - Versioning enabled
# - Lifecycle rules (expiration, transitions, noncurrent version handling)
# - Policy templates (deny_insecure_transport)
# - Custom policy (demonstrating policy merging)
# - Explicit public access block settings
# - Comprehensive tags
################################################################################

terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}

variable "name" {
  type        = string
  description = "Name prefix for all resources."
}

variable "region" {
  type        = string
  description = "AWS region to deploy resources."
  default     = "us-east-1"
}

variable "tags" {
  type        = map(string)
  description = "Additional tags for all resources."
  default     = {}
}

locals {
  common_tags = merge(
    {
      Environment = "terratest"
      ManagedBy   = "terratest"
      TestType    = "full-configuration"
      Purpose     = "comprehensive-s3-testing"
    },
    var.tags
  )

  # Custom policy that grants read access with a condition
  # This demonstrates custom policy functionality and policy merging
  custom_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowFullTestReadAccess"
        Effect = "Allow"
        Principal = {
          AWS = "*"
        }
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion"
        ]
        Resource = "arn:aws:s3:::${var.name}/*"
        Condition = {
          StringEquals = {
            "aws:PrincipalOrgID" = "o-fulltest123" # Fictitious org ID for testing
          }
        }
      }
    ]
  })
}

################################################################################
# KMS Key for S3 Encryption
################################################################################

resource "aws_kms_key" "s3" {
  description             = "KMS key for S3 bucket encryption - ${var.name}"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = local.common_tags
}

resource "aws_kms_alias" "s3" {
  name          = "alias/${var.name}"
  target_key_id = aws_kms_key.s3.key_id
}

################################################################################
# S3 Bucket with Full Configuration
################################################################################

module "s3_bucket" {
  source = "../../../../storage/s3"

  name          = var.name
  force_destroy = true # Enable for test cleanup

  #-----------------------------------------------------------------------------
  # Encryption Configuration
  #-----------------------------------------------------------------------------
  kms_key_id         = aws_kms_key.s3.arn
  bucket_key_enabled = true

  #-----------------------------------------------------------------------------
  # Versioning Configuration
  #-----------------------------------------------------------------------------
  versioning_enabled = true

  #-----------------------------------------------------------------------------
  # Public Access Block Configuration (explicitly set all settings)
  #-----------------------------------------------------------------------------
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true

  #-----------------------------------------------------------------------------
  # Lifecycle Rules Configuration
  #-----------------------------------------------------------------------------
  lifecycle_rules = [
    # Rule 1: Expire old logs
    {
      id     = "full-expire-logs"
      prefix = "logs/"
      expiration = {
        days = 90
      }
    },

    # Rule 2: Archive data with transitions
    {
      id     = "full-archive-data"
      prefix = "data/"
      transitions = [
        {
          days          = 30
          storage_class = "STANDARD_IA"
        },
        {
          days          = 90
          storage_class = "GLACIER"
        }
      ]
      expiration = {
        days = 365
      }
    },

    # Rule 3: Handle noncurrent versions
    {
      id     = "full-noncurrent-cleanup"
      prefix = "versioned/"
      noncurrent_version_expiration = {
        noncurrent_days = 30
      }
    },

    # Rule 4: Abort incomplete multipart uploads
    {
      id                                     = "full-abort-multipart"
      abort_incomplete_multipart_upload_days = 7
    }
  ]

  #-----------------------------------------------------------------------------
  # Policy Configuration (template + custom policy merging)
  #-----------------------------------------------------------------------------
  policy_templates = ["deny_insecure_transport"]
  custom_policy    = local.custom_policy

  #-----------------------------------------------------------------------------
  # Tags
  #-----------------------------------------------------------------------------
  tags = local.common_tags
}

################################################################################
# Outputs
################################################################################

# All standard S3 module outputs
output "bucket_id" {
  description = "The name of the S3 bucket."
  value       = module.s3_bucket.bucket_id
}

output "bucket_arn" {
  description = "The ARN of the S3 bucket."
  value       = module.s3_bucket.bucket_arn
}

output "bucket_domain_name" {
  description = "The bucket domain name."
  value       = module.s3_bucket.bucket_domain_name
}

output "bucket_regional_domain_name" {
  description = "The bucket region-specific domain name."
  value       = module.s3_bucket.bucket_regional_domain_name
}

output "bucket_hosted_zone_id" {
  description = "The Route 53 Hosted Zone ID for this bucket's region."
  value       = module.s3_bucket.bucket_hosted_zone_id
}

output "bucket_region" {
  description = "The AWS region this bucket resides in."
  value       = module.s3_bucket.bucket_region
}

output "bucket_policy" {
  description = "The policy document attached to the bucket."
  value       = module.s3_bucket.bucket_policy
}

output "versioning_enabled" {
  description = "Whether versioning is enabled on the bucket."
  value       = module.s3_bucket.versioning_enabled
}

output "encryption_algorithm" {
  description = "The server-side encryption algorithm used."
  value       = module.s3_bucket.encryption_algorithm
}

output "kms_key_id" {
  description = "The KMS key ID used for encryption."
  value       = module.s3_bucket.kms_key_id
}

# Additional outputs for test verification
output "kms_key_arn" {
  description = "The ARN of the KMS key created for encryption."
  value       = aws_kms_key.s3.arn
}

output "kms_key_alias" {
  description = "The alias of the KMS key."
  value       = aws_kms_alias.s3.name
}
