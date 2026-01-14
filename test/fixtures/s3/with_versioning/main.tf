################################################################################
# S3 Bucket with Versioning Fixture
#
# Creates an S3 bucket with versioning enabled for Terratest integration testing.
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
}

################################################################################
# S3 Bucket with Versioning
################################################################################

module "s3_bucket" {
  source = "../../../../storage/s3"

  name               = var.name
  force_destroy      = true # Enable for test cleanup
  versioning_enabled = true

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
