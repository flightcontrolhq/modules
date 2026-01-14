################################################################################
# S3 Bucket with Custom Policy Fixture
#
# Creates an S3 bucket with custom bucket policy and policy template merging
# for Terratest integration testing. This fixture tests the custom_policy
# feature and demonstrates policy merging with policy_templates.
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
    },
    var.tags
  )

  # Custom policy that grants read access to a specific IAM principal
  # This demonstrates custom policy functionality and policy merging
  custom_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowTestReadAccess"
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
            "aws:PrincipalOrgID" = "o-test123456" # Fictitious org ID for testing
          }
        }
      },
      {
        Sid    = "AllowTestListBucket"
        Effect = "Allow"
        Principal = {
          AWS = "*"
        }
        Action = [
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = "arn:aws:s3:::${var.name}"
        Condition = {
          StringEquals = {
            "aws:PrincipalOrgID" = "o-test123456" # Fictitious org ID for testing
          }
        }
      }
    ]
  })
}

################################################################################
# S3 Bucket with Custom Policy and Policy Template Merging
################################################################################

module "s3_bucket" {
  source = "../../../../storage/s3"

  name          = var.name
  force_destroy = true # Enable for test cleanup

  # Apply deny_insecure_transport policy template
  # This tests that custom_policy can be merged with policy_templates
  policy_templates = ["deny_insecure_transport"]

  # Custom policy with identifiable statements for test verification
  custom_policy = local.custom_policy

  tags = local.common_tags
}

################################################################################
# Outputs
################################################################################

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
  description = "The KMS key ID used for encryption (null if using SSE-S3)."
  value       = module.s3_bucket.kms_key_id
}
